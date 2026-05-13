# frozen_string_literal: true

namespace :chatwoot do
  namespace :ops do
    desc 'Check whether Uno premium plan configs and account features are applied'
    task check_uno_premium_features: :environment do
      result = Internal::UnoPremiumFeaturesHealthCheckService.new(account_id: ENV['ACCOUNT_ID']).perform

      if result.ok?
        puts 'OK: Uno premium configs and account features are applied.'
        exit 0
      end

      puts 'FAIL: Uno premium setup is not fully applied.'
      result.errors.each { |error| puts "- #{error}" }
      exit 1
    end
  end
end
