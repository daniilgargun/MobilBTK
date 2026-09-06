/**
 * Токен доступа Google по сервисному аккаунту.
 *
 * FCM с 2024 года принимает только HTTP v1, а он требует OAuth2-токен.
 * Прежний «серверный ключ» из консоли Firebase отключён, и вернуться к нему
 * нельзя. Токен живёт час, поэтому кладётся в KV: иначе каждый запуск
 * тратил бы лишний подзапрос на обмен, а их у бесплатного плана считаное
 * число.
 */

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const CACHE_KEY = 'google_access_token';

/** Срок жизни токена — час; обновляем за пять минут до конца. */
const TOKEN_TTL_SECONDS = 3600;
const REFRESH_MARGIN_SECONDS = 300;

export async function getAccessToken(
  account: ServiceAccount,
  cache: KVNamespace,
): Promise<string> {
  const cached = await cache.get(CACHE_KEY);
  if (cached) return cached;

  const token = await requestAccessToken(account);

  // KV сам удалит запись, так что протухший токен из кэша не достанется.
  await cache.put(CACHE_KEY, token, {
    expirationTtl: TOKEN_TTL_SECONDS - REFRESH_MARGIN_SECONDS,
  });

  return token;
}

async function requestAccessToken(account: ServiceAccount): Promise<string> {
  const tokenUri = account.token_uri ?? 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);

  const claims = {
    iss: account.client_email,
    scope: SCOPE,
    aud: tokenUri,
    iat: now,
    exp: now + TOKEN_TTL_SECONDS,
  };

  const jwt = await signJwt(claims, account.private_key);

  const response = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(
      `Google не выдал токен: ${response.status} ${await response.text()}`,
    );
  }

  const body = (await response.json()) as { access_token?: string };
  if (!body.access_token) throw new Error('В ответе Google нет access_token');
  return body.access_token;
}

async function signJwt(
  claims: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' };
  const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(claims),
  )}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );

  return `${unsigned}.${base64UrlBytes(new Uint8Array(signature))}`;
}

/**
 * PEM в DER.
 *
 * Ключ приходит из JSON сервисного аккаунта, где переводы строк записаны как
 * `\n`. Секреты Cloudflare хранят строку как есть, поэтому убираем и
 * настоящие переводы строк, и экранированные — иначе base64 не разберётся.
 */
function pemToDer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')
    .replace(/\s/g, '');

  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(value: string): string {
  return base64UrlBytes(new TextEncoder().encode(value));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
