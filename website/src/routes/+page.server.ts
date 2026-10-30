import { releases } from '@/server/releases';

// the hero names the newest release, when the build could read it
export const load = async () => ({ latest: (await releases()).find((r) => !r.prerelease) });
