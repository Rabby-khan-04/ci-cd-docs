import { describe, it, expect } from 'vitest';
import { sum, average } from '../src/sum.js';
import { report } from '../src/app.js';

describe('sum', () => {
  it('adds many numbers', () => {
    expect(sum(1, 2, 3)).toBe(6);
  });

  it('returns 0 for no arguments', () => {
    expect(sum()).toBe(0);
  });
});

describe('average', () => {
  it('divides total by count', () => {
    expect(average(2, 4, 6)).toBe(4);
  });

  it('returns 0 when there are no values', () => {
    expect(average()).toBe(0);
  });
});

describe('report', () => {
  it('builds a report object', () => {
    expect(report('Ada', [1, 2, 3])).toEqual({
      message: 'HELLO, ADA!',
      total: 6,
      mean: 2,
    });
  });
});