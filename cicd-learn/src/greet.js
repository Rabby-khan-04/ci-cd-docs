// A tiny pure module so it is easy to unit test.
// No I/O, no clock, no randomness: pure input -> output.
export function greet(name) {
  const clean = String(name ?? '').trim();
  if (clean === '') {
    throw new Error('name must not be empty');
  }
  return `Hello, ${clean}!`;
}

export function shout(text) {
  return String(text).toUpperCase();
}

export function slugify(text) {
  return String(text)
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function add(a, b) {
  return Number(a) + Number(b);
}