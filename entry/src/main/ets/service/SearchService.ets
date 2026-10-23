/**
 * 多源并发搜索
 */
import { BookSource } from '../model/BookSourceModels';
import { Book } from '../model/BookModels';
import { runWithConcurrency } from '../common/Concurrent';
import { BookService } from './BookService';
import { UnsupportedRuleError } from '../common/BizError';

export class SourceSearchGroup {
  source: BookSource = new BookSource();
  status: string = 'pending'; // ok | empty | failed | unsupported
  message: string = '';
  books: Book[] = [];
}

/**
 * 并发搜索所有书源，每完成一个源回调一次
 */
export async function searchAllSources(
  key: string,
  sources: BookSource[],
  onSourceDone: (group: SourceSearchGroup) => void
): Promise<void> {
  const service: BookService = BookService.getInstance();
  await runWithConcurrency<BookSource>(sources, 8, async (source: BookSource): Promise<void> => {
    const group: SourceSearchGroup = new SourceSearchGroup();
    group.source = source;
    try {
      const books: Book[] = await service.searchBySource(source, key, 1);
      group.books = books;
      group.status = books.length > 0 ? 'ok' : 'empty';
    } catch (e) {
      if (e instanceof UnsupportedRuleError) {
        group.status = 'unsupported';
        group.message = e.message;
      } else {
        group.status = 'failed';
        group.message = e instanceof Error ? e.message : String(e);
      }
    }
    onSourceDone(group);
  });
}
