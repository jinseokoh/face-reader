import { Injectable } from '@nestjs/common';
import OpenAI from 'openai';

export interface OpenAiOptions {
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
}

@Injectable()
export class OpenAiService {
  private readonly client: OpenAI;

  constructor() {
    this.client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });
  }

  async ask(prompt: string, options: OpenAiOptions = {}): Promise<string> {
    const messages: OpenAI.ChatCompletionMessageParam[] = [];

    if (options.systemPrompt) {
      messages.push({ role: 'system', content: options.systemPrompt });
    }
    messages.push({ role: 'user', content: prompt });

    const completion = await this.client.chat.completions.create({
      model: 'gpt-4o',
      messages,
      temperature: options.temperature ?? 0.7,
      max_tokens: options.maxTokens ?? 2000,
    });

    return completion.choices[0]?.message?.content ?? '';
  }
}
