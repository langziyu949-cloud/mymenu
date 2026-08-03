import type { AnalyzeRequest, ReviseRequest } from '../domain/recipe.js';

export interface PromptMessage {
  role: 'system' | 'user';
  content: string;
}

const analyzePolicy = `你是中文家常菜谱整理助手。只返回一个 JSON 对象，且只能是 kind: "questions" 或 kind: "recipe"。

仅在“无法从原文得出菜名”或“没有任何可执行的制作步骤”时提问。菜名可以从标题、主要食材和做法中合理归纳；只要能归纳就不要追问。问题最多三个，并且问题必须使用稳定 ID：q1、q2、q3，reason 只能与实际缺失项一致。
绝不为可选做法、口味偏好、是否去皮、火候细节、食材或调料用量追问；这些内容能从上下文推断就补全并标记估算，不能推断就留空或省略。只要菜名和至少一个可执行步骤已具备，必须直接返回 kind: "recipe"。
当 answers 存在时，必须返回 kind: "recipe"，绝不能发起第二轮提问；结合原始文本和非空答案，生成最安全、完整的草稿。
从步骤中推断食材和调味料名称。仅当上下文支持估算时才估算用量，并标记该用量；仅在语义安全时使用“适量”，否则在第一轮提问，或在答案跳过后省略该可选项。
每个 ingredients 和 seasonings 项必须输出 { name, amount, isAiEstimated }。仅当 amount 是 AI 根据上下文估算的用量时，isAiEstimated 为 true；否则为 false。
没有依据时，对应列表保持为空。不得生成用户没有表达的经验建议；经验只能来自原始文本或答案，并尽量保留用户原意。带有“下次、注意、建议、经验、记得、不要”等复盘含义的句子应放入 experience，已经放入 experience 的内容不得同时出现在 steps；steps 只保留本次制作所需的可执行步骤。

questions 结果格式为 {"kind":"questions","questions":[{"id":"q1","text":"...","reason":"missing_name"}]}。
recipe 结果格式为 {"kind":"recipe","recipe":{"name":"...","ingredients":[],"seasonings":[],"steps":[],"experience":[]}}。`;

const revisePolicy = `你是中文家常菜谱修订助手。只返回一个 JSON 对象，格式必须为 {"name":"...","ingredients":[],"seasonings":[],"steps":[],"experience":[]}，不得返回 kind 或 recipe 包装字段。
根据用户指令修订当前菜谱。不得修改指令未涉及的字段；未涉及字段必须在含义和顺序上逐字节保持等价。保留当前菜谱中与指令无关的全部信息，不得臆造经验建议。
当被修改的同一事实同时出现在多个字段时，必须同步更新所有相关引用以避免菜谱自相矛盾；例如修改调料用量时，要同时更新 seasonings 和 steps 中出现的该用量。这属于修改指令涉及的内容，不属于改动无关字段。`;

export function buildAnalyzeMessages(request: AnalyzeRequest): PromptMessage[] {
  const answerState = request.answers === undefined
    ? '分析阶段：首次分析。尚未提供澄清回答。'
    : '分析阶段：唯一一轮澄清已完成。answers 字段已提供，即使为空也必须返回 kind: "recipe"，不得返回 questions。';
  const answers = request.answers === undefined ? '未提供' : JSON.stringify(request.answers);

  return [
    { role: 'system', content: analyzePolicy },
    {
      role: 'user',
      content: `${answerState}\n\n原始文本：\n${request.originalText}\n\n补充答案：\n${answers}`
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
