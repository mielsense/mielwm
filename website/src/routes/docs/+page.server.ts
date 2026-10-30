import { error } from '@sveltejs/kit';
import { page } from '@/server/docs';

// the docs' front page is the introduction
export const load = () => {
	const doc = page('introduction');
	if (!doc) error(404, 'No introduction page.');
	return { doc };
};
