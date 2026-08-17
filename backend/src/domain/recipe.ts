export interface RecipeItem {
  name: string;
  amount: string;
  isAiEstimated: boolean;
}

export interface RecipeDraft {
  name: string;
  ingredients: RecipeItem[];
  seasonings: RecipeItem[];
  steps: string[];
  experience: string[];
}

export interface ClarifyingAnswer {
  questionId: string;
  answer: string;
}

export interface ClarifyingQuestion {
  id: string;
  text: string;
  reason: 'missing_name' | 'missing_steps' | 'critical_item' | 'conflict';
}

export interface AnalyzeRequest {
  originalText: string;
  answers?: ClarifyingAnswer[];
}

export type AnalyzeResult =
  | { kind: 'questions'; questions: ClarifyingQuestion[] }
  | { kind: 'guidance'; reply: string }
  | { kind: 'recipe'; recipe: RecipeDraft; reply: string };

export interface RecipeRevision {
  recipe: RecipeDraft;
  reply: string;
}

export interface ReviseRequest {
  currentRecipe: RecipeDraft;
  instruction: string;
  previousReplies?: string[];
}
