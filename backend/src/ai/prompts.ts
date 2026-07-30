import type { AnalyzeRequest, ReviseRequest } from '../domain/recipe.js';

export interface PromptMessage {
  role: 'system' | 'user';
  content: string;
}

const analyzePolicy = `你是中文家常菜谱整理助手。只返回一个 JSON 对象，且只能是 kind: "questions" 或 kind: "recipe"。

仅在缺少菜名、缺少可用步骤、存在关键未解决项或存在实质冲突时提问。问题最多三个，并且问题必须使用稳定 ID：q1、q2、q3。
当 answers 存在时，必须返回 kind: "recipe"，绝不能发起第二轮提问；结合原始文本和非空答案，生成最安全、完整的草稿。
从步骤中推断食材和调味料名称。仅当上下文支持估算时才估算用量，并标记该用量；仅在语义安全时使用“适量”，否则在第一轮提问，或在答案跳过后省略该可选项。
没有依据时，optional 列表保持为空。不得生成用户没有表达的经验建议；经验只能来自原始文本或答案。

questions 结果格式为 {"kind":"questions","questions":[{"id":"q1","text":"...","reason":"missing_name"}]}。
recipe 结果格式为 {"kind":"recipe","recipe":{"name":"...","ingredients":[],"seasonings":[],"steps":[],"experience":[]}}。`;

const revisePolicy = `你是中文家常菜谱修订助手。只返回一个 JSON 对象，格式为 {"kind":"recipe","recipe":{...}}。
根据用户指令修订当前菜谱。不得修改指令未涉及的字段；未涉及字段必须在含义和顺序上逐字节保持等价。保留当前菜谱中与指令无关的全部信息，不得臆造经验建议。`;

export function buildAnalyzeMessages(request: AnalyzeRequest): PromptMessage[] {
  return [
    { role: 'system', content: analyzePolicy },
    {
      role: 'user',
      content: `原始文本：\n${request.originalText}\n\n补充答案：\n${JSON.stringify(request.answers ?? [])}`
    }
  ];
}

export function buildReviseMessages(request: ReviseRequest): PromptMessage[] {
  return [
    { role: 'system', content: revisePolicy },
    {
      role: 'user',
      content: `当前菜谱 JSON：\n${JSON.stringify(request.currentRecipe)}\n\n修订指令：\n${request.instruction}`
    }
  ];
}
