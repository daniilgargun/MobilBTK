import { describe, expect, test } from 'vitest';
import { hashRegion, scheduleRegion } from '../src/page';

const encode = (value: string) => new TextEncoder().encode(value);
const decode = (value: Uint8Array) => new TextDecoder().decode(value);

/**
 * Страница колледжа работает на Joomla и подставляет csrf.token, который
 * меняется на каждом запросе. Пока хэш считался по всей странице, он всегда
 * отличался от прошлого — на этом и сломалась бы вся затея со сторожем.
 */
const page = (token: string, lesson: string) =>
  `<html><head>
     <script class="joomla-script-options">{"csrf.token":"${token}"}</script>
   </head><body>
     <table><tr><td>03-сен</td><td>205</td><td>${lesson}</td></tr></table>
     <footer>подвал</footer>
   </body></html>`;

describe('область расписания', () => {
  test('меняющийся токен в шапке не меняет хэш', async () => {
    const a = await hashRegion(encode(page('aaa', 'Математика')));
    const b = await hashRegion(encode(page('bbb', 'Математика')));

    expect(a).toBe(b);
  });

  test('изменение пары хэш меняет', async () => {
    const a = await hashRegion(encode(page('aaa', 'Математика')));
    const b = await hashRegion(encode(page('aaa', 'Химия')));

    expect(a).not.toBe(b);
  });

  test('берётся от первой таблицы до последней', () => {
    const region = scheduleRegion(
      encode('шапка<table>один</table>между<table>два</table>подвал'),
    );

    expect(decode(region)).toBe('<table>один</table>между<table>два</table>');
  });

  test('без таблиц возвращаются исходные байты', () => {
    const bytes = encode('<html><p>Расписания нет</p></html>');

    expect(decode(scheduleRegion(bytes))).toBe(decode(bytes));
  });

  test('хэш — это 64 шестнадцатеричных знака', async () => {
    expect(await hashRegion(encode(page('aaa', 'Математика')))).toMatch(
      /^[0-9a-f]{64}$/,
    );
  });
});
