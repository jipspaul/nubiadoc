import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Request, Response } from 'express';

interface ErrorBody {
  error: {
    code: string;
    message: string;
    request_id: string;
    details: unknown[];
  };
}

/**
 * Filtre d'exception global -> format d'erreur uniforme (docs/04 §7.2).
 * On NE log JAMAIS le corps de requête (risque PII) : seulement code + chemin + request_id.
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpException');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const requestId = randomUUID();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const code =
      exception instanceof HttpException
        ? this.toCode(exception)
        : 'internal_error';

    const message =
      exception instanceof HttpException
        ? exception.message
        : 'Une erreur interne est survenue.';

    this.logger.error(`[${requestId}] ${request.method} ${request.url} -> ${status} (${code})`);

    const body: ErrorBody = {
      error: { code, message, request_id: requestId, details: [] },
    };
    response.status(status).json(body);
  }

  private toCode(exception: HttpException): string {
    const res = exception.getResponse();
    if (typeof res === 'object' && res !== null && 'error' in res) {
      const maybe = (res as { error?: unknown }).error;
      if (typeof maybe === 'string') return maybe;
    }
    return exception.constructor.name
      .replace(/Exception$/, '')
      .replace(/([a-z])([A-Z])/g, '$1_$2')
      .toLowerCase();
  }
}
