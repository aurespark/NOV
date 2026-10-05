import 'package:flutter_test/flutter_test.dart';
import '../../../lib/src/core/models/site_rule.dart';

void main() {
  group('SiteRule Registry Tests', () {
    test('正確識別 czbooks.net 站點規則', () {
      final rule = SiteRule.findRuleForUrl('https://czbooks.net/n/skg2jdampkp');
      expect(rule.id, equals('czbooks'));
      expect(rule.name, contains('czbooks'));
      expect(rule.contentSelector, contains('.chapter-detail .content'));
      expect(rule.nextPageSelector, contains('a.next-chapter'));
    });

    test('其他未知網站回退至通用規則', () {
      final rule = SiteRule.findRuleForUrl('https://unknown-novel.org/book/123');
      expect(rule.id, equals('default'));
      expect(rule.name, equals('通用規則'));
    });
  });
}
