import { z } from 'zod';

const nonEmptyTrimmedString = z.string().trim().min(1);
const trimmedString = z.string().trim();

export const RecipeItemSchema = z.object({
  name: nonEmptyTrimmedString,
  amount: trimmedString,
  isAiEstimated: z.boolean()
}).strict();

export const RecipeDraftSchema = z.object({
  name: nonEmptyTrimmedString,
  ingredients: z.array(RecipeItemSchema).max(20),
  seasonings: z.array(RecipeItemSchema).max(20),
  steps: z.array(nonEmptyTrimmedString).min(1).max(30),
  experience: z.array(trimmedString).max(20)
}).strict();

export const ClarifyingAnswerSchema = z.object({
  questionId: nonEmptyTrimmedString,
  answer: nonEmptyTrimmedString
}).strict();

export const ClarifyingQuestionSchema = z.object({
  id: nonEmptyTrimmedString,
  text: nonEmptyTrimmedString,
  reason: z.enum(['missing_name', 'missing_steps', 'critical_item', 'conflict'])
}).strict();

export const AnalyzeRequestSchema = z.object({
  originalText: nonEmptyTrimmedString,
  answers: z.array(ClarifyingAnswerSchema).optional()
}).strict();

export const AnalyzeResultSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('questions'),
    questions: z.array(ClarifyingQuestionSchema).max(3)
  }).strict(),
  z.object({
    kind: z.literal('recipe'),
    recipe: RecipeDraftSchema
  }).strict()
]);

export const ReviseRequestSchema = z.object({
  currentRecipe: RecipeDraftSchema,
  instruction: nonEmptyTrimmedString
}).strict();
