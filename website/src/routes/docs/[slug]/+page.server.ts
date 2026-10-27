import { error } from '@sveltejs/kit';
import { page, slugs } from '@/server/docs';

export const entries = () => slugs().map((slug) => ({ slug }));

export const load = ({ params }) => {
	const doc = page(params.slug);
	if (!doc) error(404, 'No docs page by that name.');
	return { doc };
};
