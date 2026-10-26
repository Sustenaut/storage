// Every request that isn't a file in public/ (see public/_routes.json).
import { handle } from "../src/storage.js";

export const onRequest = ({ request, env }) => handle(request, env);
