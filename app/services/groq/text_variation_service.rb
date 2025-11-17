class Groq::TextVariationService
  attr_reader :text

  def self.enabled?
    ENV['GROQ_API_KEY'].present?
  end

  def initialize(text:)
    @text = text
  end

  def perform
    return text unless self.class.enabled?

    response = HTTParty.post(
      "#{base_url}/chat/completions",
      headers: request_headers,
      body: request_body.to_json
    )

    return parsed_content(response) if response.success?

    Rails.logger.error "[GROQ] HTTP #{response.code}: #{response.body}"
    text
  rescue StandardError => e
    Rails.logger.error "[GROQ] Exception: #{e.class} - #{e.message}"
    text
  end

  private

  def base_url
    ENV.fetch('GROQ_API_BASE_URL', 'https://api.groq.com/openai/v1').sub(%r{\/$}, '')
  end

  def request_headers
    {
      'Authorization' => "Bearer #{ENV['GROQ_API_KEY']}",
      'Content-Type' => 'application/json'
    }
  end

  def request_body
    prompt_template = ENV.fetch('GROQ_WHATSAPP_CAMPAIGN_PROMPT', default_prompt)
    prompt = prompt_template.gsub('{{text}}', text.to_s)
    model = ENV.fetch('GROQ_CHAT_MODEL', 'openai/gpt-oss-120b')

    {
      model: model,
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ],
      temperature: 1,
      top_p: 1,
      max_completion_tokens: 512,
      stream: false
    }
  end

  def parsed_content(response)
    content = response['choices']&.first&.dig('message', 'content')
    content.present? ? content.strip : text
  end

  def default_prompt
    <<~PROMPT
      Você é um assistente que reescreve mensagens de campanha de WhatsApp em português brasileiro.
      Reescreva o texto abaixo usando sinônimos e pequenas variações naturais,
      mantendo exatamente o mesmo significado, intenção comercial, números, URLs e emojis.
      Não traduza para outro idioma e não adicione ou remova links.
      Responda apenas com a mensagem reescrita, sem explicações adicionais.

      Texto: "{{text}}"
    PROMPT
  end
end

