import { Injectable } from '@nestjs/common';
import { HttpService } from '@nestjs/axios';
import { firstValueFrom } from 'rxjs';
import { AxiosRequestConfig, AxiosResponse } from 'axios';
import * as https from 'https';

@Injectable()
export class LinwaysService {
  private readonly baseUrl: string;
  private readonly apiPrefix: string;

  constructor(private readonly httpService: HttpService) {
    this.baseUrl = process.env.LINWAYS_BASE_URL || 'https://sfcv4.linways.com';
    this.apiPrefix = '/academics/api/v1';
  }

  private getClientConfig(cookies?: string): AxiosRequestConfig {
    return {
      baseURL: `${this.baseUrl}${this.apiPrefix}`,
      timeout: 20000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        Accept: 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        ...(cookies ? { Cookie: cookies } : {}),
      },
      httpsAgent: new https.Agent({ rejectUnauthorized: false }),
      validateStatus: () => true,
      maxRedirects: 5,
    };
  }

  async get(
    path: string,
    params?: Record<string, unknown>,
    cookies?: string,
  ): Promise<AxiosResponse> {
    const config = this.getClientConfig(cookies);
    config.params = params;
    return firstValueFrom(this.httpService.get(path, config));
  }

  async post(
    path: string,
    data?: Record<string, unknown>,
    cookies?: string,
  ): Promise<AxiosResponse> {
    const config = this.getClientConfig(cookies);
    return firstValueFrom(this.httpService.post(path, data ?? {}, config));
  }

  extractCookies(response: AxiosResponse): string[] {
    const setCookie = response.headers['set-cookie'];
    if (!setCookie) return [];
    return Array.isArray(setCookie) ? setCookie : [setCookie];
  }

  mergeCookies(existing: string | undefined, newCookies: string[]): string {
    const cookieMap = new Map<string, string>();

    if (existing) {
      existing.split(';').forEach((c) => {
        const parts = c.trim().split('=');
        if (parts.length >= 2) cookieMap.set(parts[0].trim(), parts.slice(1).join('='));
      });
    }

    newCookies.forEach((c) => {
      const parts = c.split(';')[0].trim().split('=');
      if (parts.length >= 2) cookieMap.set(parts[0].trim(), parts.slice(1).join('='));
    });

    return Array.from(cookieMap.entries())
      .map(([k, v]) => `${k}=${v}`)
      .join('; ');
  }

  extractAuthToken(cookies: string): string | null {
    const match = cookies.match(/AUTH_SESSION=([^;]+)/);
    return match ? match[1] : null;
  }
}
