import { error, redirect } from '@sveltejs/kit';
import { page, slugs } from '@/server/docs';

// pages that moved, so old links still land
const moved: Record<string, string> = { introduction: '/docs', 'getting-started': '/docs/install' };

export const entries = () => [...slugs(), ...Object.keys(moved)].map((slug) => ({ slug }));

export const load = ({ params }) => {
	if (moved[params.slug]) redirect(308, moved[params.slug]);
	const doc = page(params.slug);
	if (!doc) error(404, 'No docs page by that name.');
	return { doc };
};
