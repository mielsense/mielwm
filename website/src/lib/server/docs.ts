// Reads the repo's docs/*.md at build time. The site never holds its own copy of the text.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Marked, Renderer, type Token, type Tokens } from 'marked';
import { site } from '@/site';

const sources = import.meta.glob('../../../../docs/*.md', { query: '?raw', import: 'default', eager: true }) as Record<string, string>;
const imageUrls = import.meta.glob('../../../../docs/images/*.{png,jpg,jpeg,webp,avif,gif,svg}', {
	query: '?url',
	import: 'default',
	eager: true
}) as Record<string, string>;

// The changelog lives at the repo root, where the release workflow reads it, and shows here as one more page.
const changelog = import.meta.glob('../../../../CHANGELOG.md', { query: '?raw', import: 'default', eager: true }) as Record<string, string>;

const fileName = (path: string) => path.slice(path.lastIndexOf('/') + 1);
const markdown = new Map(
	Object.entries({ ...sources, ...changelog }).map(([path, text]) => [fileName(path).replace(/\.md$/, '').replace('CHANGELOG', 'changelog'), text])
);
/** The page a `name.md` or `../NAME.md` link points at, if the site has it. */
const pageFor = (name: string) => (markdown.has(name) ? name : markdown.has(name.toLowerCase()) ? name.toLowerCase() : undefined);
const images = new Map(Object.entries(imageUrls).map(([path, url]) => [fileName(path), url]));

export type NavPage = { slug: string; title: string; lead: string };
export type NavGroup = { title: string; pages: NavPage[] };
export type TocEntry = { id: string; text: string; depth: 2 | 3 };
export type Segment = { kind: 'html'; html: string } | { kind: 'code'; code: string; lang: string };
export type DocPage = NavPage & { segments: Segment[]; toc: TocEntry[] };
export type SearchEntry = { href: string; page: string; heading: string; text: string };

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const plain = (html: string) =>
	html
		.replace(/<[^>]+>/g, '')
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&#39;/g, "'")
		.replace(/&amp;/g, '&')
		.replace(/\s+/g, ' ')
		.trim();

/** GitHub-style heading ids, so links written against GitHub's renderer keep working. */
export const slugify = (text: string) =>
	text
		.toLowerCase()
		.trim()
		.replace(/[^\p{L}\p{N}\s_-]/gu, '')
		.replace(/\s/g, '-');

/** Width and height from a PNG or JPEG header, so images reserve their space and anchors land right. */
function dimensions(name: string): { width: number; height: number } | undefined {
	try {
		const bytes = readFileSync(join(__DOCS_DIR__, 'images', name));
		if (bytes.readUInt32BE(0) === 0x89504e47) return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
		if (bytes[0] === 0xff && bytes[1] === 0xd8) {
			for (let at = 2; at < bytes.length; ) {
				const marker = bytes[at + 1];
				// SOF0 to SOF15, minus the DHT, JPG and DAC markers
				if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker))
					return { height: bytes.readUInt16BE(at + 5), width: bytes.readUInt16BE(at + 7) };
				at += 2 + bytes.readUInt16BE(at + 2);
			}
		}
	} catch (error) {
		// the image still works, it just loads unsized and can shift the page
		console.warn(`docs: no size for images/${name}:`, (error as Error).message);
	}
}

// Code text that is only keys (⌥1, ⌃⌥G, ⇧Return, Esc) renders as a key cap instead of code.
const KEYS = /^(?:[⌘⌥⌃⇧]+(?:[A-Za-z0-9]|F\d{1,2}|Tab|Return|Space|Esc|Delete|[←→↑↓⌫\-=,./;'`[\]])?|Esc|Return|Tab|Space|F\d{1,2}|[←→↑↓]+)$/;

/** The index: `## Group` headings over `- [Title](slug.md)` items, in reading order. Missing pages are left out. */
export function navigation(): NavGroup[] {
	const index = markdown.get('README');
	const groups: NavGroup[] = [];
	if (index) {
		for (const line of index.split('\n')) {
			const group = /^##\s+(.+)/.exec(line);
			if (group) groups.push({ title: group[1].trim(), pages: [] });
			const item = /^\s*[-*]\s+\[([^\]]+)\]\((?:\.\.\/)?([\w-]+)\.md\)/.exec(line);
			const slug = item && pageFor(item[2]);
			if (item && slug) {
				if (!groups.length) groups.push({ title: 'Docs', pages: [] });
				groups.at(-1)!.pages.push({ slug, title: item[1], lead: page(slug)!.lead });
			}
		}
	} else {
		groups.push({ title: 'Docs', pages: slugs().map((slug) => ({ slug, title: page(slug)!.title, lead: page(slug)!.lead })) });
	}
	return groups.filter((group) => group.pages.length);
}

/** Every page that exists, listed or not, so each one gets a route. */
export const slugs = () => [...markdown.keys()].filter((slug) => slug !== 'README').sort();

function renderer(toc: TocEntry[]) {
	const taken = new Map<string, number>();
	const marked = new Marked({
		gfm: true,
		renderer: {
			heading({ tokens, depth }) {
				const html = this.parser.parseInline(tokens);
				const base = slugify(plain(html));
				const count = taken.get(base) ?? 0;
				taken.set(base, count + 1);
				const id = count ? `${base}-${count}` : base;
				if (depth === 2 || depth === 3) toc.push({ id, text: plain(html), depth });
				return `<h${depth} id="${id}"><a class="anchor" href="#${id}" aria-hidden="true" tabindex="-1">#</a>${html}</h${depth}>\n`;
			},
			link({ href, tokens }) {
				const text = this.parser.parseInline(tokens);
				const doc = /^(\.\.\/|\.\/)?([\w-]+)\.md(#[\w-]*)?$/.exec(href);
				// ../README.md is the repo's front page, not the docs index
				const slug = doc && !(doc[1] === '../' && doc[2] === 'README') ? pageFor(doc[2]) : undefined;
				if (doc && slug) return `<a href="/docs/${slug === 'README' ? '' : slug}${doc[3] ?? ''}">${text}</a>`;
				// a page the lead hasn't written yet reads as plain text instead of a broken link
				if (doc && doc[1] !== '../') return `<span>${text}</span>`;
				if (/^https?:/.test(href)) return `<a href="${escape(href)}" target="_blank" rel="noreferrer">${text}</a>`;
				if (/^\.\.\//.test(href)) return `<a href="${site.repo}/blob/main/${escape(href.slice(3))}" target="_blank" rel="noreferrer">${text}</a>`;
				return false;
			},
			image({ href, text }) {
				const name = /^(?:\.\/)?images\/(.+)$/.exec(href)?.[1];
				if (!name || !images.has(name)) return false;
				const img = (file: string, extra = '') => {
					const size = dimensions(file);
					// screenshots are taken at 2x, so they show at half their pixel width at most
					const box = size ? ` width="${size.width}" height="${size.height}" style="max-width: ${Math.round(size.width / 2)}px"` : '';
					return `<img src="${images.get(file)}" alt="${escape(text)}"${box} loading="lazy" decoding="async"${extra}>`;
				};
				// a -dark image with a -light sibling follows the site's theme
				const light = name.replace('-dark.', '-light.');
				const pictures = light !== name && images.has(light) ? `${img(name, ' class="only-dark"')}${img(light, ' class="only-light"')}` : img(name);
				return `<span class="frame">${pictures}</span>`;
			},
			codespan({ text }) {
				return KEYS.test(text) ? `<kbd>${escape(text)}</kbd>` : false;
			},
			table(token): string {
				return `<div class="table-scroll">${Renderer.prototype.table.call(this, token)}</div>`;
			}
		}
	});
	return marked;
}

const rendered = new Map<string, DocPage>();

/** A page, rendered once per build; the nav and the search both read every page. */
export function page(slug: string): DocPage | undefined {
	const cached = rendered.get(slug);
	if (cached) return cached;
	const source = markdown.get(slug);
	if (source === undefined) return;
	const toc: TocEntry[] = [];
	const marked = renderer(toc);
	const tokens = marked.lexer(source);
	const body = [...tokens];

	// `# Title`, then the one-line lead, then the sections
	const titleAt = body.findIndex((token) => token.type === 'heading' && token.depth === 1);
	const title = titleAt >= 0 ? (body.splice(titleAt, 1)[0] as Tokens.Heading).text : slug;
	const leadAt = body.findIndex((token) => token.type !== 'space');
	const lead = body[leadAt]?.type === 'paragraph' ? plain(marked.parseInline((body.splice(leadAt, 1)[0] as Tokens.Paragraph).text) as string) : '';

	const segments: Segment[] = [];
	let run: Token[] = [];
	const flush = () => {
		if (!run.length) return;
		segments.push({ kind: 'html', html: marked.parser(Object.assign(run, { links: tokens.links })) });
		run = [];
	};
	for (const token of body) {
		if (token.type === 'code') {
			flush();
			segments.push({ kind: 'code', code: token.text, lang: token.lang || 'text' });
		} else run.push(token);
	}
	flush();
	const doc = { slug, title: plain(title), lead, segments, toc };
	rendered.set(slug, doc);
	return doc;
}

/** One entry per section of every page, for the ⌘K search. */
export function searchIndex(): SearchEntry[] {
	const entries: SearchEntry[] = [];
	for (const slug of slugs()) {
		const doc = page(slug)!;
		const href = `/docs/${slug}`;
		let current: SearchEntry = { href, page: doc.title, heading: '', text: doc.lead };
		entries.push(current);
		for (const segment of doc.segments) {
			if (segment.kind === 'code') {
				current.text += ` ${segment.code}`;
				continue;
			}
			// split the rendered html at its h2 and h3 headings
			for (const part of segment.html.split(/(?=<h[23] id=")/)) {
				const heading = /^<h[23] id="([^"]+)">(.*?)<\/h[23]>/s.exec(part);
				if (heading) {
					current = { href: `${href}#${heading[1]}`, page: doc.title, heading: plain(heading[2]).replace(/^#/, ''), text: '' };
					entries.push(current);
					current.text = plain(part.slice(heading[0].length));
				} else current.text += ` ${plain(part)}`;
			}
		}
	}
	return entries.map((entry) => ({ ...entry, text: entry.text.trim() }));
}
