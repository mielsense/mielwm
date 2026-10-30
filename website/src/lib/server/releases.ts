// The GitHub releases, read once at build time for the download page. Any failure (no network,
// rate limit, an odd reply) gives an empty list, and the page falls back to the stable latest link.
import { site } from '@/site';

export type Dmg = { url: string; size: number };
export type Release = { version: string; date: string; prerelease: boolean; page: string; dmg?: Dmg; sha256?: string };

type Asset = { name: string; size: number; browser_download_url: string };
type GitHubRelease = { tag_name: string; published_at: string | null; prerelease: boolean; draft: boolean; html_url: string; assets: Asset[] };

const api = `https://api.github.com/repos/${new URL(site.repo).pathname.slice(1)}/releases`;
const headers: Record<string, string> = { accept: 'application/vnd.github+json' };
// CI and Vercel builds share GitHub's anonymous limit with everyone on the same address
if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

async function get(url: string): Promise<Response | undefined> {
	try {
		const response = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
		if (response.ok) return response;
		console.warn(`releases: ${url} answered ${response.status}`);
	} catch (error) {
		console.warn(`releases: ${url} failed:`, (error as Error).message);
	}
}

/** The DMG's line in SHA256SUMS, as `shasum -a 256` writes it: `<hash>  <file>`. */
export const sha256For = (sums: string, file: string) => sums.split('\n').map((line) => line.trim().split(/\s+\*?/)).find(([, name]) => name === file)?.[0];

let cached: Promise<Release[]> | undefined;

/** Published releases, newest first, with the SHA-256 of the newest stable one's DMG when its SHA256SUMS is there. */
export function releases(): Promise<Release[]> {
	return (cached ??= (async () => {
		const list = (await (await get(api))?.json().catch(() => undefined)) as GitHubRelease[] | undefined;
		if (!Array.isArray(list)) return [];
		const found: Release[] = list
			.filter((r) => !r.draft && r.published_at)
			.map((r) => {
				const version = r.tag_name.replace(/^v/, '');
				const asset = r.assets.find((a) => a.name === `mielwm-${version}.dmg`) ?? r.assets.find((a) => a.name === 'mielwm.dmg');
				return {
					version,
					date: r.published_at!,
					prerelease: r.prerelease,
					page: r.html_url,
					dmg: asset && { url: asset.browser_download_url, size: asset.size }
				};
			});
		const latest = found.find((r) => !r.prerelease);
		const raw = list.find((r) => r.tag_name.replace(/^v/, '') === latest?.version);
		const sums = raw?.assets.find((a) => a.name === 'SHA256SUMS');
		if (latest && sums) {
			const text = await (await get(sums.browser_download_url))?.text().catch(() => undefined);
			latest.sha256 = text ? sha256For(text, `mielwm-${latest.version}.dmg`) : undefined;
		}
		return found;
	})());
}
