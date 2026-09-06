import { describe, expect, test } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { hashRegion, scheduleRegion } from '../src/page';

/**
 * Снимок настоящей страницы bartc.by. Нужен, чтобы проверять извлечение
 * области на живой разметке, а не только на игрушечной.
 *
 * Второй «снимок» получается подменой csrf.token. Три копии, снятые подряд,
 * отличались ровно одной строкой — той, где этот токен, — поэтому хранить
 * их все смысла нет, а полмегабайта чужой разметки в репозитории лишние.
 */
const page = new Uint8Array(
  readFileSync(
    fileURLToPath(new URL('./fixtures/schedule-page.html', import.meta.url)),
  ),
);

const text = new TextDecoder().decode(page);

/** Тот же снимок с другим значением csrf.token — как при втором запросе. */
const withOtherToken = new TextEncoder().encode(
  text.replace(/"csrf\.token":"[0-9a-f]+"/, '"csrf.token":"deadbeef"'),
);

const sha256 = async (bytes: Uint8Array) => {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
};

describe('снимок настоящей страницы', () => {
  test('в снимке действительно есть меняющийся токен', () => {
    expect(text).toMatch(/"csrf\.token":"[0-9a-f]+"/);
  });

  test('смена токена не меняет хэш области', async () => {
    expect(await hashRegion(page)).toBe(await hashRegion(withOtherToken));
  });

  test('а хэш страницы целиком — меняет', async () => {
    expect(await sha256(page)).not.toBe(await sha256(withOtherToken));
  });

  test('область вдвое меньше страницы и не пустая', () => {
    const region = scheduleRegion(page);

    expect(region.length).toBeGreaterThan(10_000);
    expect(region.length).toBeLessThan(page.length / 2);
  });

  test('область начинается таблицей и ею же кончается', () => {
    const region = new TextDecoder().decode(scheduleRegion(page));

    expect(region.startsWith('<table')).toBe(true);
    expect(region.endsWith('</table>')).toBe(true);
  });
});
