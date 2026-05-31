#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";

const [, , unsignedXpiPath, manifestPath, secretPath, outputPath] = process.argv;

if (!unsignedXpiPath || !manifestPath || !secretPath || !outputPath) {
  console.error(
    "Usage: node scripts/sign_amo_firefox.mjs <unsigned-xpi> <manifest> <secret-json> <output-xpi>",
  );
  process.exit(1);
}

const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
const secret = JSON.parse(await fs.readFile(secretPath, "utf8"));
const firefoxSecret = secret.firefox ?? secret.mozilla ?? secret.amo ?? secret;
const addonId = manifest?.browser_specific_settings?.gecko?.id;
const version = manifest?.version;

if (!addonId || !version) {
  throw new Error("Firefox manifest must contain browser_specific_settings.gecko.id and version.");
}

const issuer =
  firefoxSecret.api_key ??
  firefoxSecret.jwt_issuer ??
  firefoxSecret.issuer ??
  firefoxSecret.key ??
  firefoxSecret.jwt_key;
const apiSecret =
  firefoxSecret.api_secret ??
  firefoxSecret.jwt_secret ??
  firefoxSecret.secret ??
  firefoxSecret.hmac_secret;

if (!issuer || !apiSecret) {
  throw new Error(
    "secret.json must contain Firefox AMO credentials. Expected firefox.issuer/firefox.secret or flat api_key/api_secret-style fields.",
  );
}

const token = createJwt(issuer, apiSecret);
const endpoint = `https://addons.mozilla.org/api/v4/addons/${encodeURIComponent(addonId)}/versions/${encodeURIComponent(version)}/`;
const xpiBytes = await fs.readFile(unsignedXpiPath);

console.error(`[AMO] Uploading unsigned XPI for ${addonId} ${version}`);
let status = await uploadVersion(endpoint, token, unsignedXpiPath, xpiBytes);
if (status?.errors) {
  throw new Error(`AMO upload rejected: ${JSON.stringify(status.errors)}`);
}
console.error(`[AMO] Initial status: ${summarizeStatus(status)}`);

for (let attempt = 0; attempt < 60; attempt += 1) {
  if (status.processed && !status.valid) {
    throw new Error(`AMO validation failed: ${JSON.stringify(status.validation_results)}`);
  }
  if (status.reviewed && status.passed_review && status.files?.[0]?.download_url) {
    console.error("[AMO] Review passed, downloading signed XPI");
    await downloadSignedFile(status.files[0].download_url, token, outputPath);
    console.log(`Signed Firefox XPI saved to ${outputPath}`);
    process.exit(0);
  }
  console.error(`[AMO] Waiting for signing (${attempt + 1}/60): ${summarizeStatus(status)}`);
  await sleep(5000);
  status = await fetchJson(endpoint, token);
}

throw new Error("Timed out waiting for AMO signing to finish.");

async function uploadVersion(endpoint, token, unsignedXpiPath, xpiBytes) {
  const form = new FormData();
  form.set(
    "upload",
    new Blob([xpiBytes], { type: "application/x-xpinstall" }),
    basename(unsignedXpiPath),
  );

  const response = await fetch(endpoint, {
    method: "PUT",
    headers: {
      Authorization: `JWT ${token}`,
      Accept: "application/json",
    },
    body: form,
  });

  if (response.status === 409) {
    console.error("[AMO] Version already exists on AMO, fetching current signing status");
    return fetchJson(endpoint, token);
  }
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`AMO upload failed: ${response.status} ${errorText}`);
  }
  return response.json();
}

async function fetchJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Authorization: `JWT ${token}`,
      Accept: "application/json",
    },
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`AMO status request failed: ${response.status} ${errorText}`);
  }
  return response.json();
}

async function downloadSignedFile(url, token, outputPath) {
  const response = await fetch(url, {
    headers: {
      Authorization: `JWT ${token}`,
    },
    redirect: "follow",
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`AMO signed download failed: ${response.status} ${errorText}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  await fs.writeFile(outputPath, bytes);
}

function createJwt(issuer, secret) {
  const header = { alg: "HS256", typ: "JWT" };
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload = {
    iss: issuer,
    jti: crypto.randomUUID(),
    iat: issuedAt,
    exp: issuedAt + 300,
  };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.createHmac("sha256", secret).update(unsignedToken).digest();
  return `${unsignedToken}.${base64url(signature)}`;
}

function base64url(value) {
  return Buffer.from(value)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function basename(path) {
  return path.split(/[\\/]/).at(-1) ?? "addon.xpi";
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function summarizeStatus(status) {
  if (!status || typeof status !== "object") {
    return "unknown";
  }

  const parts = [
    `processed=${formatValue(status.processed)}`,
    `valid=${formatValue(status.valid)}`,
    `reviewed=${formatValue(status.reviewed)}`,
    `passed_review=${formatValue(status.passed_review)}`,
  ];

  if (Array.isArray(status.files) && status.files.length > 0) {
    parts.push(`files=${status.files.length}`);
    parts.push(`download_url=${Boolean(status.files[0]?.download_url)}`);
  }

  if (status.validation_results) {
    parts.push("validation_results=present");
  }

  return parts.join(", ");
}

function formatValue(value) {
  return value == null ? "null" : String(value);
}
