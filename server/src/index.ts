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
    await check(env);
  },

  /**
   * Ручная проверка: `curl 'https://<воркер>/check?token=...'`.
   *
   * Ждать пятнадцать минут, чтобы понять, работает ли развёртывание,
   * невыносимо. Отдаёт то же, что записал бы в лог.
   *
   * Пароль обязателен: без него любой желающий мог бы дёргать этой ссылкой
   * сайт колледжа сколько угодно раз. Пароль не задан — точка входа просто
   * не существует, чтобы забытая настройка не оставляла её открытой.
   */
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    const authorized =
      Boolean(env.CHECK_TOKEN) &&
      (url.searchParams.get('token') === env.CHECK_TOKEN ||
        request.headers.get('Authorization') === `Bearer ${env.CHECK_TOKEN}`);

    if (url.pathname !== '/check' || !authorized) {
      return new Response('БТК Расписание: сторож страницы.\n', {
        status: 404,
      });
    }

    try {
      const result = await check(env);
      return Response.json(result);
    } catch (error) {
      return Response.json({ error: String(error) }, { status: 500 });
    }
  },
};

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
  const response = await fetch(env.SCHEDULE_URL, {
    headers: HEADERS,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!response.ok) {
    // Сайт колледжа лежит или отвечает ошибкой. Будить приложение незачем:
    // оно упрётся ровно в то же самое.
    console.log(`Страница не отдалась: ${response.status}`);
    return { status: 'download-failed', httpStatus: response.status };
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  const hash = await hashRegion(bytes);

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
