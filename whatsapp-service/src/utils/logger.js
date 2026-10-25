const fs = require('fs');
const path = require('path');

let winston;
try {
  winston = require('winston');
} catch (_) {}

let logger;

const logDir = path.join(__dirname, '../../logs');
if (!fs.existsSync(logDir)) {
  try {
    fs.mkdirSync(logDir, { recursive: true });
  } catch (_) {}
}

if (winston) {
  logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
      winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
      winston.format.printf(({ timestamp, level, message, ...meta }) => {
        const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
        return `[${timestamp}] [${level.toUpperCase()}] ${message}${metaStr}`;
      })
    ),
    transports: [
      new winston.transports.Console(),
      new winston.transports.File({
        filename: path.join(logDir, 'whatsapp_service.log'),
        maxsize: 5242880,
        maxFiles: 5,
      }),
      new winston.transports.File({
        filename: path.join(logDir, 'whatsapp_errors.log'),
        level: 'error',
      }),
    ],
  });
} else {
  const formatMsg = (level, ...args) => {
    const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
    return `[${timestamp}] [${level.toUpperCase()}] ${args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(' ')}`;
  };
  logger = {
    info: (...args) => console.log(formatMsg('info', ...args)),
    warn: (...args) => console.warn(formatMsg('warn', ...args)),
    error: (...args) => console.error(formatMsg('error', ...args)),
    debug: (...args) => {
      if (process.env.LOG_LEVEL === 'debug') {
        console.log(formatMsg('debug', ...args));
      }
    },
  };
}

module.exports = logger;
