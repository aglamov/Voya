import crypto from "node:crypto";
import http2 from "node:http2";

export type APNsAlert = {
  title: string;
  body: string;
  threadId?: string;
  data?: Record<string, unknown>;
};

type APNsSendResult = {
  configured: boolean;
  attempted: number;
  sent: number;
  failed: number;
  errors: string[];
  invalidDeviceTokens: string[];
};

class APNsDeliveryError extends Error {
  constructor(message: string, readonly invalidToken: boolean) {
    super(message);
  }
}

function apnsConfig() {
  const keyId = process.env.APNS_KEY_ID?.trim();
  const teamId = process.env.APNS_TEAM_ID?.trim();
  const bundleId = process.env.APNS_BUNDLE_ID?.trim() ?? "com.aglamov.voya";
  const privateKey = process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, "\n").trim();
  const environment = process.env.APNS_ENV?.trim() === "production" ? "production" : "development";

  if (!keyId || !teamId || !bundleId || !privateKey) {
    return undefined;
  }

  return {
    keyId,
    teamId,
    bundleId,
    privateKey,
    host: environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com"
  };
}

function base64url(input: string | Buffer) {
  return (Buffer.isBuffer(input) ? input : Buffer.from(input))
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function derSignatureToJose(signature: Buffer) {
  if (signature[0] !== 0x30) {
    throw new Error("Invalid ECDSA signature.");
  }

  let offset = signature[1] > 0x80 ? 2 + (signature[1] - 0x80) : 2;
  if (signature[offset] !== 0x02) {
    throw new Error("Invalid ECDSA signature R component.");
  }
  const rLength = signature[offset + 1];
  const r = signature.subarray(offset + 2, offset + 2 + rLength);
  offset += 2 + rLength;

  if (signature[offset] !== 0x02) {
    throw new Error("Invalid ECDSA signature S component.");
  }
  const sLength = signature[offset + 1];
  const s = signature.subarray(offset + 2, offset + 2 + sLength);

  return Buffer.concat([leftPad(r), leftPad(s)] as Uint8Array[]);
}

function leftPad(value: Buffer) {
  const trimmed = value[0] === 0 ? value.subarray(1) : value;
  if (trimmed.length > 32) {
    return trimmed.subarray(trimmed.length - 32);
  }
  if (trimmed.length === 32) {
    return trimmed;
  }

  return Buffer.concat([Buffer.alloc(32 - trimmed.length), trimmed] as Uint8Array[]);
}

function authToken(config: NonNullable<ReturnType<typeof apnsConfig>>) {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const payload = base64url(JSON.stringify({ iss: config.teamId, iat: Math.floor(Date.now() / 1000) }));
  const unsigned = `${header}.${payload}`;
  const signer = crypto.createSign("sha256");
  signer.update(unsigned);
  signer.end();
  const signature = derSignatureToJose(signer.sign(config.privateKey));

  return `${unsigned}.${base64url(signature)}`;
}

async function sendOne(deviceToken: string, alert: APNsAlert, token: string, config: NonNullable<ReturnType<typeof apnsConfig>>) {
  const client = http2.connect(config.host);
  const payload = JSON.stringify({
    aps: {
      alert: {
        title: alert.title,
        body: alert.body
      },
      sound: "default",
      "thread-id": alert.threadId
    },
    voya: alert.data ?? {}
  });

  return await new Promise<void>((resolve, reject) => {
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${token}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10"
    });
    let responseBody = "";
    let status = 0;

    request.setEncoding("utf8");
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    request.on("data", (chunk) => {
      responseBody += chunk;
    });
    request.on("end", () => {
      client.close();
      if (status >= 200 && status < 300) {
        resolve();
      } else {
        let reason = responseBody;
        try {
          reason = (JSON.parse(responseBody) as { reason?: string }).reason ?? responseBody;
        } catch {
          // APNs may return an empty or non-JSON proxy response.
        }
        reject(new APNsDeliveryError(
          reason || `APNs returned HTTP ${status}`,
          reason === "BadDeviceToken" || reason === "Unregistered"
        ));
      }
    });
    request.on("error", (error) => {
      client.close();
      reject(error);
    });
    request.end(payload);
  });
}

export async function sendAPNsAlert(deviceTokens: string[], alert: APNsAlert): Promise<APNsSendResult> {
  const config = apnsConfig();
  if (!config) {
    return {
      configured: false,
      attempted: deviceTokens.length,
      sent: 0,
      failed: deviceTokens.length,
      errors: deviceTokens.length ? ["APNs environment variables are not configured."] : [],
      invalidDeviceTokens: []
    };
  }

  const token = authToken(config);
  const result: APNsSendResult = {
    configured: true,
    attempted: deviceTokens.length,
    sent: 0,
    failed: 0,
    errors: [],
    invalidDeviceTokens: []
  };

  const uniqueTokens = [...new Set(deviceTokens)];
  for (let index = 0; index < uniqueTokens.length; index += 10) {
    await Promise.all(uniqueTokens.slice(index, index + 10).map(async (deviceToken) => {
      try {
        await sendOne(deviceToken, alert, token, config);
        result.sent += 1;
      } catch (error) {
        result.failed += 1;
        result.errors.push(error instanceof Error ? error.message : "APNs push failed.");
        if (error instanceof APNsDeliveryError && error.invalidToken) {
          result.invalidDeviceTokens.push(deviceToken);
        }
      }
    }));
  }

  return result;
}
