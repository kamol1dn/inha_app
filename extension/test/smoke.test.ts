import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './setup.ts';
import { parseHtml, text } from '../src/core/dom.ts';

test('fixtures and DOMParser load', () => {
  const doc = parseHtml(fixture('eclass_login.html'));
  assert.ok(text(doc.body).length > 0);
});
