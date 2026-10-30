// The docs borrow the landing page's look: each group has a mesh and a sticker glyph, each page a glyph.
import { BookIcon, ChartIcon, CommandIcon, DownloadIcon, FileIcon, HashIcon, LayersIcon, LifebuoyIcon, ListIcon, SearchIcon, SparkleIcon, SwapIcon, TerminalIcon, WrenchIcon, type IconData } from '@/icons';
import { mesh } from '@/mesh';

// tint is the mesh's base color, for the flat panel behind a page title
export type Look = { icon: IconData; mesh: string; tint: string };

const groups: Record<string, Look> = {
	'Get started': { icon: SparkleIcon, mesh: mesh.orange, tint: '#f8b46b' },
	'Using mielwm': { icon: LayersIcon, mesh: mesh.violet, tint: '#a78bfa' },
	'Coming from AeroSpace': { icon: SwapIcon, mesh: mesh.coral, tint: '#fb7185' },
	Reference: { icon: BookIcon, mesh: mesh.sky, tint: '#7dd3fc' }
};

const pages: Record<string, IconData> = {
	introduction: BookIcon,
	install: DownloadIcon,
	'first-steps': SparkleIcon,
	workspaces: LayersIcon,
	layouts: HashIcon,
	stacks: LayersIcon,
	floating: SwapIcon,
	focus: CommandIcon,
	overview: SearchIcon,
	keyboard: CommandIcon,
	trackpad: SparkleIcon,
	'menu-bar': HashIcon,
	import: DownloadIcon,
	aerospace: SwapIcon,
	'compatible-apps': LayersIcon,
	settings: WrenchIcon,
	configuration: FileIcon,
	'window-rules': FileIcon,
	'command-line': TerminalIcon,
	performance: ChartIcon,
	troubleshooting: LifebuoyIcon,
	changelog: ListIcon
};

// a group or page the index adds later still gets a look, so the docs never break on new content
export const groupLook = (title: string | undefined): Look => (title && groups[title]) || { icon: BookIcon, mesh: mesh.indigo, tint: '#6366f1' };
export const pageIcon = (slug: string): IconData => pages[slug] ?? BookIcon;
