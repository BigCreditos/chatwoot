import { buildPortalArticleURL, buildPortalURL } from '../portalHelper';

describe('PortalHelper', () => {
  describe('buildPortalURL', () => {
    it('returns the correct url', () => {
      window.viperchatConfig = {
        hostURL: 'https://app.viperchat.com',
        helpCenterURL: 'https://help.viperchat.com',
      };
      expect(buildPortalURL('handbook')).toEqual(
        'https://help.viperchat.com/hc/handbook'
      );
      window.viperchatConfig = {};
    });
  });

  describe('buildPortalArticleURL', () => {
    it('returns the correct url', () => {
      window.viperchatConfig = {
        hostURL: 'https://app.viperchat.com',
        helpCenterURL: 'https://help.viperchat.com',
      };
      expect(
        buildPortalArticleURL('handbook', 'culture', 'fr', 'article-slug')
      ).toEqual('https://help.viperchat.com/hc/handbook/articles/article-slug');
      window.viperchatConfig = {};
    });

    it('returns the correct url with custom domain', () => {
      window.viperchatConfig = {
        hostURL: 'https://app.viperchat.com',
        helpCenterURL: 'https://help.viperchat.com',
      };
      expect(
        buildPortalArticleURL(
          'handbook',
          'culture',
          'fr',
          'article-slug',
          'custom-domain.dev'
        )
      ).toEqual('https://custom-domain.dev/hc/handbook/articles/article-slug');
    });

    it('handles https in custom domain correctly', () => {
      window.viperchatConfig = {
        hostURL: 'https://app.viperchat.com',
        helpCenterURL: 'https://help.viperchat.com',
      };
      expect(
        buildPortalArticleURL(
          'handbook',
          'culture',
          'fr',
          'article-slug',
          'https://custom-domain.dev'
        )
      ).toEqual('https://custom-domain.dev/hc/handbook/articles/article-slug');
    });

    it('uses hostURL when helpCenterURL is not available', () => {
      window.viperchatConfig = {
        hostURL: 'https://app.viperchat.com',
        helpCenterURL: '',
      };
      expect(
        buildPortalArticleURL('handbook', 'culture', 'fr', 'article-slug')
      ).toEqual('https://app.viperchat.com/hc/handbook/articles/article-slug');
    });
  });
});
