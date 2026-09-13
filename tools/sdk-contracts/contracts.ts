import type * as Anthropic from '@anthropic-ai/sdk/resources/messages/messages';
import type * as AnthropicShared from '@anthropic-ai/sdk/resources/shared';
import type * as Responses from 'openai/resources/responses/responses';
import type * as Chat from 'openai/resources/chat/completions/completions';
import type * as OpenAIShared from 'openai/resources/shared';

export type AnthropicMessage = Anthropic.Message;
export type AnthropicMessageParam = Anthropic.MessageParam;
export type AnthropicStopReason = Anthropic.StopReason;
export type AnthropicStreamEvent = Anthropic.RawMessageStreamEvent;
export type AnthropicRequest = Anthropic.MessageCreateParams;
export type AnthropicCountTokensRequest = Anthropic.MessageCountTokensParams;
export type AnthropicError = AnthropicShared.ErrorResponse;
export type OpenAIResponseInput = Responses.ResponseInputItem;
export type OpenAIResponseOutput = Responses.ResponseOutputItem;
export type OpenAIResponseStreamEvent = Responses.ResponseStreamEvent;
export type OpenAIResponseRequest = Responses.ResponseCreateParams;
export type OpenAIResponseRequestBase = Responses.ResponseCreateParamsBase;
export type OpenAIResponseCompactRequest = Responses.ResponseCompactParams;
export type OpenAIError = OpenAIShared.ErrorObject;
export type OpenAIChatMessage = Chat.ChatCompletionMessageParam;
export type OpenAIChatChunk = Chat.ChatCompletionChunk;
export type OpenAIChatCompletion = Chat.ChatCompletion;
export type OpenAIChatRequest = Chat.ChatCompletionCreateParams;

// A local characterization fixture, never an upstream SDK contract.
export interface PresenceProbe {
  requiredNullable: string | null;
  optionalNullable?: string | null;
  optionalValue?: string;
  closedValue: 'a' | 'b';
  openValue: 'known' | string;
}
