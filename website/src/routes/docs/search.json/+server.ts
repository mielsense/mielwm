import { json } from '@sveltejs/kit';
import { searchIndex } from '@/server/docs';

export const prerender = true;

export const GET = () => json(searchIndex());
