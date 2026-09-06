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
   * Ручная проверка: `curl https://<воркер>/check`.
   *
   * Ждать пятнадцать минут, чтобы понять, работает ли развёртывание,
   * невыносимо. Отдаёт то же, что записал бы в лог.
   */
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname !== '/check') {
      return new Response('БТК Расписание: сторож страницы. См. /check\n', {
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
  status: 'unchanged' | 'first-run' | 'notified' | 'download-failed';
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

  await env.STATE.put(HASH_KEY, hash);

  if (previous === null) {
    // Первый запуск после развёртывания: сравнивать не с чем. Если сейчас
    // разослать сообщение, все пользователи получат «расписание изменилось»
    // просто потому, что сервер поднялся.
    console.log(`Первый запуск, запомнили хэш ${hash}`);
    return { status: 'first-run', hash };
  }

  const account = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount;
  const accessToken = await getAccessToken(account, env.STATE);

  await sendWakeUp({
    projectId: env.FIREBASE_PROJECT_ID,
    accessToken,
    topic: env.FCM_TOPIC,
    pageHash: hash,
  });

  console.log(`Страница изменилась (${previous} → ${hash}), разослано`);
  return { status: 'notified', hash };
}
