export interface DemoRecipeDraft {
  name: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
}

export interface DemoRevisionResult {
  recipe: DemoRecipeDraft;
  reply: string;
  changed: boolean;
}

const NAME_LIMIT: number = 18;
const NAME_DELIMITERS: string[] = ['：', ':', '，', ',', '。', '\n'];

function firstDelimiterIndex(text: string): number {
  let result: number = -1;
  NAME_DELIMITERS.forEach((delimiter: string) => {
    const index: number = text.indexOf(delimiter);
    if (index >= 0 && (result < 0 || index < result)) {
      result = index;
    }
  });
  return result;
}

function splitSteps(text: string): string[] {
  return text
    .split(/[。\n]/)
    .map((step: string) => step.trim())
    .filter((step: string) => step.length > 0);
}

function cleanRecipeName(value: string): string {
  let name: string = value.trim();
  name = name
    .replace(/^今天做的/, '')
    .replace(/^今天做了/, '')
    .replace(/^我今天做的/, '')
    .replace(/^我做的/, '')
    .replace(/很成功$/, '')
    .replace(/做成功了$/, '')
    .replace(/成功了$/, '')
    .trim();
  const calledIndex: number = name.indexOf('叫');
  if (calledIndex >= 0 && calledIndex < name.length - 1) {
    name = name.slice(calledIndex + 1).trim();
  }
  return name;
}

function isCookingStep(sentence: string): boolean {
  const actions: string[] = [
    '洗', '切', '泡', '腌', '焯', '炒', '煮', '蒸', '炖', '煎', '烤', '拌', '炸',
    '放', '加入', '倒入', '盛出', '翻炒', '收汁', '出锅'
  ];
  return actions.some((action: string) => sentence.includes(action));
}

function extractItems(text: string, keywords: string[]): string[] {
  const result: string[] = [];
  keywords.forEach((keyword: string) => {
    if (!text.includes(keyword)) {
      return;
    }
    const amountPattern: RegExp = new RegExp(`([一二两三四五六七八九十半\\d.]+\\s*(?:斤|克|公斤|个|颗|只|块|片|勺|汤匙|茶匙|毫升|ml))\\s*${keyword}`);
    const match: RegExpMatchArray | null = text.match(amountPattern);
    result.push(match === null ? `${keyword} · 适量（AI估算）` : `${keyword} · ${match[1].replace(/\\s/g, '')}`);
  });
  return result;
}

function extractExperience(text: string): string[] {
  return splitSteps(text).filter((sentence: string) =>
    sentence.includes('下次') || sentence.includes('不要') || sentence.includes('记得') ||
    sentence.includes('要分') || sentence.includes('这样') || sentence.includes('注意'));
}

export function generateDemoRecipe(rawText: string): DemoRecipeDraft {
  const text: string = rawText.trim();
  if (text.length === 0) {
    throw new Error('先说说这道菜是怎么做的');
  }

  const delimiterIndex: number = firstDelimiterIndex(text);
  const rawName: string = delimiterIndex >= 0 ? text.slice(0, delimiterIndex) : text;
  const cleanedName: string = cleanRecipeName(rawName);
  const name: string = (cleanedName.length > 0 ? cleanedName : rawName.trim()).slice(0, NAME_LIMIT);
  const remaining: string = delimiterIndex >= 0 ? text.slice(delimiterIndex + 1) : '';
  const parsedSteps: string[] = splitSteps(remaining);
  const experience: string[] = extractExperience(text);
  const cookingSteps: string[] = parsedSteps.filter((sentence: string) =>
    isCookingStep(sentence) && !experience.includes(sentence));
  const steps: string[] = cookingSteps.length > 0 ? cookingSteps : (parsedSteps.length > 0 ? parsedSteps : [text]);
  const ingredientKeywords: string[] = [
    '牛腩', '牛肉', '猪肉', '鸡肉', '鸡蛋', '番茄', '西红柿', '土豆', '洋葱', '茄子',
    '黄瓜', '豆腐', '青椒', '白菜', '萝卜', '香菇', '虾', '鱼'
  ];
  const seasoningKeywords: string[] = [
    '生抽', '老抽', '盐', '糖', '醋', '料酒', '蚝油', '胡椒', '豆瓣酱', '淀粉', '葱', '姜', '蒜'
  ];

  return {
    name,
    steps,
    ingredients: extractItems(text, ingredientKeywords),
    seasonings: extractItems(text, seasoningKeywords),
    experience
  };
}

function replaceAmount(items: string[], instruction: string): string[] {
  const marker: string = '改成';
  const markerIndex: number = instruction.indexOf(marker);
  if (markerIndex <= 0) {
    return items;
  }
  const itemName: string = instruction.slice(0, markerIndex).trim();
  const amount: string = instruction.slice(markerIndex + marker.length).replace(/[。！!]/g, '').trim();
  return items.map((item: string) => item.includes(itemName) ? `${itemName} · ${amount}` : item);
}

export function reviseDemoRecipe(current: DemoRecipeDraft, rawInstruction: string): DemoRevisionResult {
  const instruction: string = rawInstruction.trim();
  const recipe: DemoRecipeDraft = {
    name: current.name,
    steps: current.steps.slice(),
    ingredients: current.ingredients.slice(),
    seasonings: current.seasonings.slice(),
    experience: current.experience.slice()
  };

  if (instruction.startsWith('菜名改成') || instruction.startsWith('菜名改为')) {
    recipe.name = instruction.slice(4).replace(/[。！!]/g, '').trim();
    return { recipe, reply: '菜名已经改好了，你再看看。', changed: recipe.name.length > 0 };
  }
  if (instruction.includes('经验里加上') || instruction.includes('经验加上') || instruction.includes('经验补充')) {
    const content: string = instruction
      .replace('经验里加上', '')
      .replace('经验加上', '')
      .replace('经验补充', '')
      .replace(/[。！!]/g, '')
      .trim();
    if (content.length > 0) {
      recipe.experience.push(content);
      return { recipe, reply: '这条经验已经记进卡片了。', changed: true };
    }
  }
  if (instruction.includes('步骤加上') || instruction.includes('增加一步')) {
    const content: string = instruction.replace('步骤加上', '').replace('增加一步', '').replace(/[。！!]/g, '').trim();
    if (content.length > 0) {
      recipe.steps.push(content);
      return { recipe, reply: '新步骤已经加在最后。', changed: true };
    }
  }
  const stepMatch: RegExpMatchArray | null = instruction.match(/第(\\d+)步(?:改成|改为)(.+)/);
  if (stepMatch !== null) {
    const stepIndex: number = Number.parseInt(stepMatch[1]) - 1;
    const content: string = stepMatch[2].replace(/[。！!]/g, '').trim();
    if (stepIndex >= 0 && stepIndex < recipe.steps.length && content.length > 0) {
      recipe.steps[stepIndex] = content;
      return { recipe, reply: `第 ${stepIndex + 1} 步已经更新。`, changed: true };
    }
  }
  if (instruction.includes('改成')) {
    const revisedIngredients: string[] = replaceAmount(recipe.ingredients, instruction);
    const revisedSeasonings: string[] = replaceAmount(recipe.seasonings, instruction);
    if (JSON.stringify(revisedIngredients) !== JSON.stringify(recipe.ingredients) ||
      JSON.stringify(revisedSeasonings) !== JSON.stringify(recipe.seasonings)) {
      recipe.ingredients = revisedIngredients;
      recipe.seasonings = revisedSeasonings;
      return { recipe, reply: '用量已经按你说的修改。', changed: true };
    }
  }

  return {
    recipe,
    reply: '这句话我暂时没改明白。你可以说“菜名改成…”“第2步改成…”或“经验里加上…”。',
    changed: false
  };
}
