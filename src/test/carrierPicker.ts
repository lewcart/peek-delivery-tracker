import { screen, waitFor, within } from '@testing-library/react';
import type { UserEvent } from '@testing-library/user-event';
import { SELECTABLE_CARRIERS } from '../lib/carriers';

/** The open carrier picker. */
export function carrierPicker(): HTMLElement {
  return screen.getByRole('dialog', { name: 'Carrier' });
}

/** Waits until the open picker lists every carrier from A to Z: it draws the first rows at once and the rest a batch a frame. */
export async function everyCarrierListed(picker = carrierPicker()): Promise<void> {
  // Counted without a role query, which names every row each time it is asked.
  await waitFor(() => {
    if (picker.querySelectorAll('[data-letter] > [role="option"]').length < SELECTABLE_CARRIERS.length) throw new Error('The A to Z list is still filling in.');
  });
}

/** Opens the carrier picker with `opener`, searches for `name` and picks it. */
export async function pickCarrier(user: UserEvent, opener: HTMLElement, name: string): Promise<void> {
  await user.click(opener);
  const picker = await screen.findByRole('dialog', { name: 'Carrier' });
  // Pasted in one go: typing searches and redraws the results once per letter,
  // which held the tests that pick carriers close to their time limit under load.
  await user.click(within(picker).getByRole('combobox', { name: 'Search carriers' }));
  await user.paste(name);
  await user.click(within(picker).getByRole('option', { name }));
}
