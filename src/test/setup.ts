import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup, configure } from '@testing-library/react';

class MemoryStorage implements Storage {
  #values = new Map<string, string>();

  get length() {
    return this.#values.size;
  }

  clear() {
    this.#values.clear();
  }

  getItem(key: string) {
    return this.#values.get(String(key)) ?? null;
  }

  key(index: number) {
    return [...this.#values.keys()][index] ?? null;
  }

  removeItem(key: string) {
    this.#values.delete(String(key));
  }

  setItem(key: string, value: string) {
    this.#values.set(String(key), String(value));
  }
}

// Components wait in real time before they act (a typing pause of 800 ms, a carrier lookup 350 ms
// after the number settles), and the carrier picker fills in every carrier over a few frames: one
// role query over it takes a few hundred milliseconds. Testing Library's one second left too little
// for the rest on a busy machine, so its waits fail there while the page is still on its way.
configure({ asyncUtilTimeout: 5_000 });

// Node 24 reserves a global localStorage binding that can mask JSDOM's
// origin-backed implementation inside isolated test workers.
if (typeof window !== 'undefined') Object.defineProperty(window, 'localStorage', {
  configurable: true,
  value: new MemoryStorage(),
});

afterEach(async () => {
  cleanup();
  if (typeof window === 'undefined') return;
  window.localStorage.clear();
  // jsdom moves through history.back() two tasks later. A test that closes a
  // parcel last would otherwise move the next test's address.
  for (let task = 0; task < 2; task++) await new Promise((resolve) => setImmediate(resolve));
});
