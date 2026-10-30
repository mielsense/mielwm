import { changelogSection } from '@/server/docs';
import { releases } from '@/server/releases';

export const load = async () => {
	const all = await releases();
	const latest = all.find((r) => !r.prerelease);
	return {
		latest,
		older: all.filter((r) => r !== latest),
		// with no release list, the newest version the changelog has
		notes: changelogSection(latest?.version)
	};
};
