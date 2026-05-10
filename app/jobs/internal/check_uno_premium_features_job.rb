# frozen_string_literal: true

class Internal::CheckUnoPremiumFeaturesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    result = Internal::UnoPremiumFeaturesHealthCheckService.new.perform

    if result.ok?
      Rails.logger.info('[Internal::CheckUnoPremiumFeaturesJob] Uno premium setup is valid')
    else
      Rails.logger.error("[Internal::CheckUnoPremiumFeaturesJob] Uno premium setup drift detected: #{result.errors.join('; ')}")
    end
  end
end
