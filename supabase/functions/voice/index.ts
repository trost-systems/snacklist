import { telemetryFor, withTelemetry } from '../_shared/telemetry.ts';
import { productionDeps } from './deps.ts';
import { createHandler } from './handler.ts';

const telemetry = telemetryFor('voice');

Deno.serve(withTelemetry('voice', createHandler(productionDeps(telemetry)), telemetry));
