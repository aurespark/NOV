class SiteRule {
  final String id;
  final String name;
  final String domainPattern;
  final String? startReadSelector;
  final String contentSelector;
  final String nextPageSelector;
  final List<String> filterSelectors;
  final String? titleSelector;

  const SiteRule({
    required this.id,
    required this.name,
    required this.domainPattern,
    this.startReadSelector,
    required this.contentSelector,
    required this.nextPageSelector,
    this.filterSelectors = const [],
    this.titleSelector,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'domainPattern': domainPattern,
      'startReadSelector': startReadSelector,
      'contentSelector': contentSelector,
      'nextPageSelector': nextPageSelector,
      'filterSelectors': filterSelectors.join(','),
      'titleSelector': titleSelector,
    };
  }

  factory SiteRule.fromMap(Map<String, dynamic> map) {
    return SiteRule(
      id: map['id'] as String,
      name: map['name'] as String,
      domainPattern: map['domainPattern'] as String,
      startReadSelector: map['startReadSelector'] as String?,
      contentSelector: map['contentSelector'] as String,
      nextPageSelector: map['nextPageSelector'] as String,
      filterSelectors: (map['filterSelectors'] as String?)
              ?.split(',')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      titleSelector: map['titleSelector'] as String?,
    );
  }

  /// 根據目標網址自動匹配專屬站點規則
  static SiteRule findRuleForUrl(String url) {
    if (url.contains('czbooks.net')) {
      return const SiteRule(
        id: 'czbooks',
        name: '小說狂人 (czbooks)',
        domainPattern: r'czbooks\.net',
        // czbooks 書籍首頁的「開始閱讀」或第一章連結
        startReadSelector: '.read-btn, a.btn:contains("開始閱讀"), ul.chapter-list li:first-child a, .chapter-list a',
        contentSelector: '.chapter-detail .content, div.content',
        nextPageSelector: 'a.next-chapter, a:contains("下一章"), a:contains("下一頁")',
        filterSelectors: ['.ad', '.advertisement', 'script', 'style', '.banner'],
        titleSelector: '.chapter-detail h1, h1.title, h1',
      );
    }

    return defaultRule();
  }

  static SiteRule defaultRule() {
    return const SiteRule(
      id: 'default',
      name: '通用規則',
      domainPattern: '.*',
      startReadSelector: 'a:contains("開始閱讀"), a:contains("开始阅读"), .read-btn, ul li:first-child a',
      contentSelector: '#content, .content, #chaptercontent, article',
      nextPageSelector: 'a:contains("下一頁"), a:contains("下一页"), a:contains("下一章"), .next-page',
      filterSelectors: [
        'script',
        'style',
        '.ad',
        '.advertisement',
        '[style*="display:none"]',
        '[style*="display: none"]',
        '[style*="visibility:hidden"]',
      ],
      titleSelector: 'h1, .title, .chapter-title',
    );
  }
}
