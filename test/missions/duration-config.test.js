import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Process, Building } from '@influenceth/sdk';

// Match the conversions used when publishing ProcessType components.
const duration = (process) => ({
  setup: Math.round(process.setupTime || 0),
  recipe: Math.round((process.recipeTime || 0) * 1000)
});

test('every configured process retains positive duration after serialization', () => {
  for (const process of Object.values(Process.TYPES)) {
    const { setup, recipe } = duration(process);
    assert.ok(setup > 0 || recipe > 0, `${process.name} (${process.i}) has zero duration`);
  }
});

test('all processing definitions have positive setup independent of recipe quantity', () => {
  for (const process of Object.values(Process.TYPES).filter((p) => p.processorType)) {
    assert.ok(duration(process).setup > 0, `${process.name} has no fixed setup time`);
  }
});

test('every constructible building has positive construction time', () => {
  for (const building of Object.values(Building.TYPES).filter((b) => b.processType)) {
    const process = Process.TYPES[building.processType];
    assert.ok(process, `${building.name} has no construction recipe`);
    const { setup, recipe } = duration(process);
    assert.ok(setup > 0 || recipe > 0, `${building.name} has zero construction time`);
  }
});
