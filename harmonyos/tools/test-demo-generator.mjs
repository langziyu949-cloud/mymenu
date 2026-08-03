import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const source = resolve(
  'entry/src/main/ets/domain/DemoRecipeGenerator.ets'
);
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'kitchen-master-generator-'));
const executableSource = join(temporaryDirectory, 'DemoRecipeGenerator.ts');

copyFileSync(source, executableSource);
const { generateDemoRecipe, reviseDemoRecipe } = await import(pathToFileURL(executableSource));

process.on('exit', () => {
  rmSync(temporaryDirectory, { recursive: true, force: true });
});

test('derives the trimmed recipe name before the first supported delimiter', () => {
  const result = generateDemoRecipe('  番茄炒蛋：先炒鸡蛋。再炒番茄  ');

  assert.equal(result.name, '番茄炒蛋');
  assert.deepEqual(result.steps, ['先炒鸡蛋', '再炒番茄']);
});

test('caps a derived recipe name at 18 characters', () => {
  const result = generateDemoRecipe('一二三四五六七八九十一二三四五六七八九十：完成');

  assert.equal(result.name, '一二三四五六七八九十一二三四五六七八');
  assert.equal(result.name.length, 18);
});

test('splits non-empty remaining text on periods and newlines in order', () => {
  const result = generateDemoRecipe('红烧肉，焯水。\n  炒糖色\n炖四十分钟。 ');

  assert.deepEqual(result.steps, ['焯水', '炒糖色', '炖四十分钟']);
});

test('uses the full input as one step when no remainder exists', () => {
  const result = generateDemoRecipe('蒸十分钟');

  assert.equal(result.name, '蒸十分钟');
  assert.deepEqual(result.steps, ['蒸十分钟']);
});

test('extracts known ingredients and marks missing amounts as estimates', () => {
  const result = generateDemoRecipe('番茄炒蛋：两个鸡蛋炒熟。番茄炒出汁。加一勺盐');

  assert.deepEqual(result.ingredients, ['鸡蛋 · 两个', '番茄 · 适量（AI估算）']);
  assert.deepEqual(result.seasonings, ['盐 · 一勺']);
  assert.deepEqual(result.experience, []);
});

test('keeps only explicitly stated experience', () => {
  const result = generateDemoRecipe('番茄牛腩：炖一个小时。番茄要分两次放，这样味道更明显。下次老抽少放一点');

  assert.deepEqual(result.experience, ['番茄要分两次放，这样味道更明显', '下次老抽少放一点']);
});

test('cleans conversational prefixes from recipe names and keeps experience out of steps', () => {
  const result = generateDemoRecipe('今天做的番茄牛腩很成功。牛腩先焯水。小火炖一个小时。番茄要分两次放，这样味道更明显');

  assert.equal(result.name, '番茄牛腩');
  assert.deepEqual(result.steps, ['牛腩先焯水', '小火炖一个小时']);
  assert.deepEqual(result.experience, ['番茄要分两次放，这样味道更明显']);
});

test('supports conversational recipe revisions', () => {
  const recipe = generateDemoRecipe('番茄炒蛋：鸡蛋炒熟。番茄炒出汁。放老抽');
  const renamed = reviseDemoRecipe(recipe, '菜名改成家常番茄炒蛋');
  const experienced = reviseDemoRecipe(renamed.recipe, '经验里加上番茄分两次放');

  assert.equal(renamed.recipe.name, '家常番茄炒蛋');
  assert.deepEqual(experienced.recipe.experience, ['番茄分两次放']);
});

test('rejects blank input with the required message', () => {
  assert.throws(
    () => generateDemoRecipe(' \n  '),
    { message: '先说说这道菜是怎么做的' }
  );
});
