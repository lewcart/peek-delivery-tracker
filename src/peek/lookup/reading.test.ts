import { describe, expect, it } from 'vitest';
import { checkDigitTrouble, looksLikeNumber, numbersInText, readText } from './reading';
import rules from '../../../shared/reading.json';

// Every number here is fictional.
describe('reading the field', () => {
  it('reads one number out of a number, a link and a message', () => {
    expect(readText('1ZDEMO202600000001').match).toMatchObject({ trackingNumber: '1ZDEMO202600000001', carrier: 'ups', source: 'number' });
    expect(readText('https://www.dhl.com/ch-en/home/tracking.html?tracking-id=1234567899&submit=1').match)
      .toMatchObject({ trackingNumber: '1234567899', carrier: 'dhl', source: 'link' });
    expect(readText('Your parcel 99.34.123456.78901234 is on its way').match)
      .toMatchObject({ trackingNumber: '99.34.123456.78901234', carrier: 'swiss-post', source: 'text' });
    expect(readText('  ').match.trackingNumber).toBe('');
    // Six letters typed alone are a GLS Track ID; in a message they are a word.
    expect(readText('ABCDEF').match).toMatchObject({ trackingNumber: 'ABCDEF', source: 'number', confidence: 'low' });
  });

  it('takes the one number a message introduces even when its shape proves no carrier', () => {
    const message = 'Hi Alex, good news: your order has shipped!\nTrack it with DHL: 1234567899\nExpected delivery: Wednesday';
    expect(readText(message).match).toMatchObject({ trackingNumber: '1234567899', carrier: 'unknown', confidence: 'low', source: 'text' });
  });

  it('lists every certain number in a text once, in the order written, links included', () => {
    const text = 'Your order ships in 3 parcels:\nUPS 1ZDEMO202600000001\nUPS 1ZDEMO202600000029\nSwiss Post 99.34.123456.78901234\nagain: 1zdemo202600000001';
    expect(numbersInText(text).map(({ normalized, match }) => [normalized, match.carrier])).toEqual([
      ['1ZDEMO202600000001', 'ups'], ['1ZDEMO202600000029', 'ups'], ['993412345678901234', 'swiss-post'],
    ]);
    expect(readText(text).numbers).toHaveLength(3);
    expect(numbersInText('https://www.dhl.com/track?tracking-id=1234567899 and 1ZDEMO202600000001').map(({ normalized }) => normalized))
      .toEqual(['1234567899', '1ZDEMO202600000001']);
    // One number is not a choice.
    expect(readText('1ZDEMO202600000001').numbers).toEqual([]);
    // Numbers on neighbouring lines never run together.
    expect(numbersInText('RR123456785CH\nLX123456785DE').map(({ normalized }) => normalized)).toEqual(['RR123456785CH', 'LX123456785DE']);
  });

  // The iPhone's Add sheet replays the same examples.
  it.each(rules.examples)('reads a message’s number, or a shop’s order number: $text', (example) => {
    const reading = readText(example.text);
    expect(reading.order).toBe(example.shop);
    if ('number' in example) expect(reading.match.trackingNumber).toBe(example.number);
    if ('carrier' in example) expect(reading.match).toMatchObject({ carrier: example.carrier, confidence: 'high' });
  });

  it('sets a typed number in the label’s type, and prose as prose', () => {
    expect(looksLikeNumber('1ZDEMO2026')).toBe(true);
    expect(looksLikeNumber('99.34.123456.78901234')).toBe(true);
    expect(looksLikeNumber('1Z 999 AA1 01')).toBe(true);
    expect(looksLikeNumber('Your parcel 1234567899')).toBe(false);
    expect(looksLikeNumber('https://example.test/1234567899')).toBe(false);
    expect(looksLikeNumber('')).toBe(false);
  });
});

describe('check digits', () => {
  it('suggests the digit a letter was read for', () => {
    expect(checkDigitTrouble('LX1234567B5DE')).toEqual({ suggestion: 'LX123456785DE' });
    expect(checkDigitTrouble('lx 1234567b5 de')).toEqual({ suggestion: 'LX123456785DE' });
    expect(checkDigitTrouble('RR12345678SCH')).toEqual({ suggestion: 'RR123456785CH' });
    // A digit where a letter stands.
    expect(checkDigitTrouble('1X123456785DE')).toEqual({ suggestion: 'IX123456785DE' });
    expect(checkDigitTrouble('LX123456785D3')).toBeNull();
  });

  it('asks without guessing when a digit is wrong: many corrections would add up', () => {
    expect(checkDigitTrouble('LX123456789DE')).toEqual({ suggestion: null });
    expect(checkDigitTrouble('LX123465785DE')).toEqual({ suggestion: null });
  });

  it('leaves alone what adds up, and what is not a postal number', () => {
    expect(checkDigitTrouble('LX123456785DE')).toBeNull();
    expect(checkDigitTrouble('1ZDEMO202600000001')).toBeNull();
    expect(checkDigitTrouble('1234567899')).toBeNull();
    expect(checkDigitTrouble('DEMOGLS202600')).toBeNull();
    // Letters that stand for no digit make it another kind of number.
    expect(checkDigitTrouble('LX12X4567Y5DE')).toBeNull();
  });
});
