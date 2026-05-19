import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || '1m',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  const baseUrl = __ENV.BASE_URL || 'http://127.0.0.1:5035';
  const res = http.get(`${baseUrl}/weather/local`);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response has weather payload': (r) => r.body && r.body.includes('temperatureC'),
  });

  sleep(1);
}
