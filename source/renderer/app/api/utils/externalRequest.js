// @flow
import { omit } from 'lodash';
import { ALLOWED_EXTERNAL_HOSTNAMES } from '../../config/urlsConfig';

export type HttpOptions = {
  hostname: string,
  method: string,
  path?: string,
  port?: number,
  protocol?: string,
  headers?: {
    'Content-Type': string,
    'Content-Length': number,
  },
};

export const externalRequest = (httpOptions: HttpOptions): Promise<any> => {
  return new Promise((resolve, reject) => {
    if (!ALLOWED_EXTERNAL_HOSTNAMES.includes(httpOptions.hostname)) {
      return reject(new Error('Hostname not allowed'));
    }
    const { hostname, protocol = 'https' } = httpOptions;
    const options = omit(httpOptions, 'protocol');
    const requestMethod = global[protocol].request;
    const request = requestMethod(options);

    request.on('response', response => {
      let body = '';
      response.on('data', chunk => {
        body += chunk;
      });
      response.on('error', error => reject(error));
      response.on('end', () => {
        const parsedBody =
          hostname === 'www.google.com' ? '' : JSON.parse(body);
        return resolve(parsedBody);
      });
    });
    request.on('error', error => reject(error));
    return request.end();
  });
};
