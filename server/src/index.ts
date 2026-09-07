/**
 * Следит за страницей расписания БТК и будит приложение, когда она меняется.
 *
 * Зачем это вообще нужно. Уведомления об изменениях приложение строит само:
 * фоновая задача Workmanager раз в 15 минут качает страницу и сравнивает с
 * тем, что уже знает. Беда в том, что Android — и особенно оболочка Samsung —
 * фоновые задачи усыпляет, и до пользователя уведомление просто не доходит.
 * Сообщение FCM с высоким приоритетом Doze пробивает, поэтому проверку
 * времени вынесли сюда, а телефон теперь только откликается.
 *
 * Воркер намеренно ничего не разбирает и ничего не хранит, кроме хэша
 * страницы: см. комментарий в fcm.ts.
 */

import { getAccessToken, type ServiceAccount } from './google-auth';
import { sendWakeUp } from './fcm';
import { hashRegion } from './page';

export interface Env {
  STATE: KVNamespace;
  SCHEDULE_URL: string;
  FCM_TOPIC: string;
  FIREBASE_PROJECT_ID: string;
  /** Целиком JSON сервисного аккаунта Firebase. Секрет, не переменная. */
  FCM_SERVICE_ACCOUNT: string;
  /** Пароль ручной проверки. Не задан — `/check` выключен. */
  CHECK_TOKEN?: string;
}

const HASH_KEY = 'page_hash';

/** Последний отказ сайта: когда, с каким кодом и что ответил. */
const FAILURE_KEY = 'last_failure';

/** Отметка последнего запуска — по ней видно, ходит ли расписание вообще. */
const LAST_RUN_KEY = 'last_run';

const DOWNLOAD_ATTEMPTS = 3;
const RETRY_DELAY_MS = 3000;

/** Тот же User-Agent, что у приложения: на пустой сайт отдаёт 403. */
const HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  Accept: 'text/html,application/xhtml+xml',
};

/** Столько же, сколько ждёт приложение. */
const TIMEOUT_MS = 25_000;

export default {
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    const result = await check(env);

    // Отметка о каждом запуске по расписанию.
    //
    // Без неё нельзя отличить «запуски идут, но сайт не отвечает» от
    // «запусков нет вовсе», а лечится это совершенно по-разному. Логи
    // воркера тут не помогают: они живут считаные минуты и смотреть их
    // можно только вживую, а разбираться приходится задним числом.
    await env.STATE.put(
      LAST_RUN_KEY,
      JSON.stringify({ at: new Date().toISOString(), ...result }),
    );
  },

  /**
   * Две точки входа, обе требуют пароль:
   *
   * - `/check?token=...` — проверить страницу прямо сейчас. Ждать
   *   пятнадцать минут, чтобы понять, работает ли развёртывание, невыносимо.
   * - `/state?token=...` — что известно о прошлых запусках: последний
   *   запуск по расписанию, последний отказ сайта, запомненный хэш. Ничего
   *   не запрашивает и сайт колледжа не трогает.
   *
   * Пароль обязателен: без него любой желающий мог бы дёргать `/check`
   * сколько угодно раз, а через него и сайт колледжа. Пароль не задан —
   * точек входа просто нет, чтобы забытая настройка не оставляла их
   * открытыми.
   */
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    const authorized =
      Boolean(env.CHECK_TOKEN) &&
      (url.searchParams.get('token') === env.CHECK_TOKEN ||
        request.headers.get('Authorization') === `Bearer ${env.CHECK_TOKEN}`);

    const known = url.pathname === '/check' || url.pathname === '/state';
    if (!known || !authorized) {
      return new Response('БТК Расписание: сторож страницы.\n', {
        status: 404,
      });
    }

    try {
      if (url.pathname === '/state') {
        const [lastRun, lastFailure, hash] = await Promise.all([
          env.STATE.get(LAST_RUN_KEY),
          env.STATE.get(FAILURE_KEY),
          env.STATE.get(HASH_KEY),
        ]);
        return Response.json({
          now: new Date().toISOString(),
          lastRun: lastRun ? JSON.parse(lastRun) : null,
          lastFailure: lastFailure ? JSON.parse(lastFailure) : null,
          pageHash: hash,
        });
      }

      const result = await check(env);
      return Response.json(result);
    } catch (error) {
      return Response.json({ error: String(error) }, { status: 500 });
    }
  },
};

type Download =
  | { ok: true; bytes: Uint8Array }
  | { ok: false; status: number; body: string };

/**
 * Загружает страницу, повторяя попытку при отказе.
 *
 * Сайт колледжа — небольшой Joomla на PHP 7.4, и он время от времени
 * отвечает воркеру пятисоткой, хотя тому же запросу с обычной машины
 * отвечает нормально. Одна попытка раз в 15 минут означала, что такой отказ
 * съедает всю проверку целиком: расписание меняется, а уведомление не
 * уходит. Три попытки подряд стоят два лишних подзапроса и закрывают
 * случайные отказы.
 *
 * `cacheTtl: 0` обязателен. Cloudflare по умолчанию кэширует ответы на
 * GET-запросы из воркера, а сторож весь построен на сравнении «что было» и
 * «что стало»: получив копию из кэша, он не заметил бы изменения вовсе.
 */
async function downloadPage(env: Env): Promise<Download> {
  let last: { status: number; body: string } = {
    status: 0,
    body: 'попыток не было',
  };

  for (let attempt = 1; attempt <= DOWNLOAD_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(env.SCHEDULE_URL, {
        headers: HEADERS,
        signal: AbortSignal.timeout(TIMEOUT_MS),
        cf: { cacheTtl: 0, cacheEverything: false },
      });

      if (response.ok) {
        return { ok: true, bytes: new Uint8Array(await response.arrayBuffer()) };
      }

      last = {
        status: response.status,
        body: (await response.text()).slice(0, 300),
      };
    } catch (error) {
      last = { status: 0, body: String(error).slice(0, 300) };
    }

    if (attempt < DOWNLOAD_ATTEMPTS) {
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    }
  }

  return { ok: false, ...last };
}

type CheckResult = {
  status:
    | 'unchanged'
    | 'first-run'
    | 'notified'
    | 'download-failed'
    | 'not-configured';
  hash?: string;
  httpStatus?: number;
};

async function check(env: Env): Promise<CheckResult> {
  const download = await downloadPage(env);

  if (!download.ok) {
    // Сайт колледжа лежит или отвечает ошибкой. Будить приложение незачем:
    // оно упрётся ровно в то же самое.
    //
    // Причину записываем в хранилище: отказ случается когда придётся, а
    // логи воркера живут считаные минуты и смотреть их можно только вживую.
    // Без этой записи «почему сегодня не пришло уведомление» выяснить
    // нельзя вообще.
    await env.STATE.put(
      FAILURE_KEY,
      JSON.stringify({
        at: new Date().toISOString(),
        status: download.status,
        body: download.body,
      }),
    );
    console.log(`Страница не отдалась: ${download.status} ${download.body}`);
    return { status: 'download-failed', httpStatus: download.status };
  }

  const hash = await hashRegion(download.bytes);

  const previous = await env.STATE.get(HASH_KEY);
  if (previous === hash) {
    return { status: 'unchanged', hash };
  }

  if (previous === null) {
    // Первый запуск после развёртывания: сравнивать не с чем. Если сейчас
    // разослать сообщение, все пользователи получат «расписание изменилось»
    // просто потому, что сервер поднялся.
    await env.STATE.put(HASH_KEY, hash);
    console.log(`Первый запуск, запомнили хэш ${hash}`);
    return { status: 'first-run', hash };
  }

  if (!env.FCM_SERVICE_ACCOUNT) {
    // Воркер развёрнут, а ключ ещё не положили. Хэш намеренно не
    // запоминаем: иначе это изменение расписания пропало бы навсегда, и
    // после появления ключа никто бы о нём не узнал.
    console.log('Ключ сервисного аккаунта не задан, рассылка пропущена');
    return { status: 'not-configured', hash };
  }

  const account = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount;
  const accessToken = await getAccessToken(account, env.STATE);

  await sendWakeUp({
    projectId: env.FIREBASE_PROJECT_ID,
    accessToken,
    topic: env.FCM_TOPIC,
    pageHash: hash,
  });

  // Запоминаем только после успешной рассылки. Если FCM откажет или сеть
  // подведёт, следующий запуск снова увидит изменение и повторит попытку —
  // а не сочтёт, что об этом изменении уже сообщили.
  await env.STATE.put(HASH_KEY, hash);

  console.log(`Страница изменилась (${previous} → ${hash}), разослано`);
  return { status: 'notified', hash };
}
