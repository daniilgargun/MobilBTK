/**
 * Область страницы, по которой считается хэш, и сам хэш.
 *
 * Зеркало `ParserService.scheduleRegion` в приложении: если правится одно,
 * правится и другое. Обе стороны должны одинаково отвечать на вопрос
 * «изменилось ли расписание», иначе сервер будет будить приложение впустую
 * или, что хуже, молчать при настоящем изменении.
 */

const OPEN = '<table';
const CLOSE = '</table>';

/**
 * Байты от первой таблицы до последней.
 *
 * Хэшировать всю страницу нельзя: сайт колледжа работает на Joomla, и в
 * разметке сидит `csrf.token`, который меняется на каждом запросе. Хэш всей
 * страницы поэтому отличается всегда, и «изменилось ли расписание» по нему
 * не определить. Проверено на живой странице: три запроса подряд дали три
 * разных хэша страницы и один и тот же хэш этой области.
 *
 * Заодно область вдвое меньше страницы — 67 КБ из 172.
 *
 * Поиск по байтам, а не разбор HTML: воркеру достаточно знать факт
 * изменения, разбирать расписание он не должен. Если таблиц не нашлось,
 * возвращаются исходные байты — хуже, чем было, не станет.
 */
export function scheduleRegion(bytes: Uint8Array): Uint8Array {
  const start = indexOf(bytes, OPEN, 0);
  if (start < 0) return bytes;

  const end = lastIndexOf(bytes, CLOSE);
  if (end < start) return bytes;

  return bytes.subarray(start, end + CLOSE.length);
}

/** SHA-256 области расписания в виде hex-строки. */
export async function hashRegion(bytes: Uint8Array): Promise<string> {
  const region = scheduleRegion(bytes);
  const digest = await crypto.subtle.digest('SHA-256', region);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function indexOf(bytes: Uint8Array, needle: string, from: number): number {
  const codes = [...needle].map((c) => c.charCodeAt(0));
  outer: for (let i = from; i <= bytes.length - codes.length; i++) {
    for (let j = 0; j < codes.length; j++) {
      if (bytes[i + j] !== codes[j]) continue outer;
    }
    return i;
  }
  return -1;
}

function lastIndexOf(bytes: Uint8Array, needle: string): number {
  const codes = [...needle].map((c) => c.charCodeAt(0));
  outer: for (let i = bytes.length - codes.length; i >= 0; i--) {
    for (let j = 0; j < codes.length; j++) {
      if (bytes[i + j] !== codes[j]) continue outer;
    }
    return i;
  }
  return -1;
}
