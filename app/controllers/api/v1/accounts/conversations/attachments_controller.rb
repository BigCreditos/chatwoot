class Api::V1::Accounts::Conversations::AttachmentsController < Api::V1::Accounts::Conversations::BaseController
  def destroy
    delete_all = ActiveModel::Type::Boolean.new.cast(params[:delete_all])
    attachment_ids = normalized_attachment_ids

    if !delete_all && attachment_ids.blank?
      return render json: { error: 'attachment_ids or delete_all is required' }, status: :unprocessable_entity
    end

    attachments = @conversation.attachments
    attachments = attachments.where(id: attachment_ids) unless delete_all
    count = attachments.count

    if count.zero?
      return render json: { count: 0 }, status: :ok
    end

    Conversations::AttachmentsBulkDeleteJob.perform_later(
      @conversation,
      attachment_ids: attachment_ids,
      delete_all: delete_all
    )

    render json: { count: count }, status: :accepted
  end

  private

  def normalized_attachment_ids
    Array(params[:attachment_ids]).map(&:to_i).reject(&:zero?).uniq
  end
end

Api::V1::Accounts::Conversations::AttachmentsController.prepend_mod_with('Api::V1::Accounts::Conversations::AttachmentsController')
