import { describe, it, expect } from 'vitest';
import { greet, shout, slugify, add } from '../src/greet.js';

describe('greet', () => {
  it('greets by name', () => {
    expect(greet('Ada')).toBe('Hello, Ada!');
  });

  it('trims surrounding whitespace', () => {
    expect(greet('  Ada  ')).toBe('Hello, Ada!');
  });

  it('throws on an empty name', () => {
    expect(() => greet('   ')).toThrow('name must not be empty');
  });
});

describe('shout', () => {
  it('uppercases text', () => {
    expect(shout('hey')).toBe('HEY');
  });
});

describe('slugify', () => {
  it('lowercases and joins words with dashes', () => {
    expect(slugify('Hello World')).toBe('hello-world');
  });

  it('strips leading and trailing dashes', () => {
    expect(slugify('  Spaces Everywhere  ')).toBe('spaces-everywhere');
  });

  it('collapses punctuation runs', () => {
    expect(slugify('a -- b')).toBe('a-b');
  });
});

describe('add', () => {
  it('adds two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });
});