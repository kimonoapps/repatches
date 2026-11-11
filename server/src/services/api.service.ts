import { Injectable, NotAcceptableException } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';
import { escape } from 'lodash-es';
import { readFileSync } from 'node:fs';
import { ImmichCookie } from 'src/enum.js';
import { ConfigRepository } from 'src/repositories/config.repository.js';
import { LoggingRepository } from 'src/repositories/logging.repository.js';
import { AuthService } from 'src/services/auth.service.js';
import { SharedLinkService } from 'src/services/shared-link.service.js';
import { OpenGraphTags } from 'src/utils/misc.js';
import { respondWithCookie } from 'src/utils/response.js';

// Kimono: the pages a signed-out visitor may be sent to Kimono sign-in from, server-side, before any HTML.
const AUTO_LAUNCH_PATHS = new Set(['/', '/auth/login']);
// Upstream's own opt-outs (web/src/lib/utils.ts oauth.isAutoLaunchDisabled) plus OAuth callbacks.
const isAutoLaunchOptOut = (query: Request['query']) =>
  query.autoLaunch === '0' ||
  query.password === '1' ||
  query.password === 'true' ||
  'code' in query ||
  'error' in query;

// Kimono: the phone app comes from Kimono, so "Get the app" anywhere in the web app goes to Kimono's own page.
const GET_APP_PATH = '/get-app';
const getAppUrl = () => {
  const url = process.env.KIMONO_GET_APP_URL ?? '';
  return /^https?:\/\//.test(url) ? url : null;
};

export const render = (index: string, meta: OpenGraphTags) => {
  const [title, description, imageUrl] = [meta.title, meta.description, meta.imageUrl].map((item) =>
    item ? escape(item) : '',
  );

  const tags = `
    <meta name="description" content="${description}" />

    <!-- Facebook Meta Tags -->
    <meta property="og:type" content="website" />
    <meta property="og:title" content="${title}" />
    <meta property="og:description" content="${description}" />
    ${imageUrl ? `<meta property="og:image" content="${imageUrl}" />` : ''}`;

  return index.replace('<!-- metadata:tags -->', () => tags);
};

@Injectable()
export class ApiService {
  constructor(
    private authService: AuthService,
    private sharedLinkService: SharedLinkService,
    private configRepository: ConfigRepository,
    private logger: LoggingRepository,
  ) {
    this.logger.setContext(ApiService.name);
  }

  /** Kimono: 302 a signed-out visitor to the OAuth provider when auto-launch is on, so no login form ever renders. */
  private async redirectToOAuth(request: Request, res: Response) {
    if (!AUTO_LAUNCH_PATHS.has(request.path) || isAutoLaunchOptOut(request.query)) {
      return false;
    }

    try {
      if (await this.authService.isAuthenticatedRequest(request.headers, request.path)) {
        return false;
      }

      const autoLaunch = await this.authService.getOAuthAutoLaunch(`${request.protocol}://${request.host}`);
      if (!autoLaunch) {
        return false;
      }

      respondWithCookie(res, null, {
        isSecure: request.secure,
        values: [
          { key: ImmichCookie.OAuthState, value: autoLaunch.state },
          { key: ImmichCookie.OAuthCodeVerifier, value: autoLaunch.codeVerifier ?? '' },
        ],
      });
      res.header('Cache-Control', 'no-store').redirect(302, autoLaunch.url);
      return true;
    } catch (error) {
      // Sign-in provider unreachable: fall back to the web app, which shows the error and any password form.
      this.logger.warn(`OAuth auto-launch failed, serving the login page: ${error}`);
      return false;
    }
  }

  ssr(excludePaths: string[]) {
    const { resourcePaths } = this.configRepository.getEnv();

    let index = '';
    try {
      index = readFileSync(resourcePaths.web.indexHtml).toString();
    } catch {
      this.logger.warn(`Unable to open ${resourcePaths.web.indexHtml}, skipping SSR.`);
    }

    return async (request: Request, res: Response, next: NextFunction) => {
      const method = request.method.toLowerCase();
      if (
        request.url.startsWith('/api') ||
        (method !== 'get' && method !== 'head') ||
        excludePaths.some((item) => request.url.startsWith(item))
      ) {
        return next();
      }

      const responseType = request.accepts('text/html');
      if (!responseType) {
        throw new NotAcceptableException(
          `The route ${request.path} was requested as ${request.header('accept')}, but only returns text/html`,
        );
      }

      const kimonoGetApp = request.path === GET_APP_PATH ? getAppUrl() : null;
      if (kimonoGetApp) {
        const query = request.url.indexOf('?');
        return res.header('Cache-Control', 'no-store').redirect(302, kimonoGetApp + (query === -1 ? '' : request.url.slice(query)));
      }

      if (await this.redirectToOAuth(request, res)) {
        return;
      }

      let status = 200;
      let html = index;

      const defaultDomain = request.host ? `${request.protocol}://${request.host}` : undefined;

      let meta: OpenGraphTags | null = null;

      const shareKey = request.url.match(/^\/share\/(.+)$/);
      if (shareKey) {
        try {
          const key = shareKey[1];
          const auth = await this.authService.validateSharedLinkKey(key);
          meta = await this.sharedLinkService.getMetadataTags(auth, defaultDomain);
        } catch {
          status = 404;
        }
      }

      const shareSlug = request.url.match(/^\/s\/(.+)$/);
      if (shareSlug) {
        try {
          const slug = shareSlug[1];
          const auth = await this.authService.validateSharedLinkSlug(slug);
          meta = await this.sharedLinkService.getMetadataTags(auth, defaultDomain);
        } catch {
          status = 404;
        }
      }

      if (meta) {
        html = render(index, meta);
      }

      res.status(status).type(responseType).header('Cache-Control', 'no-store').send(html);
    };
  }
}
