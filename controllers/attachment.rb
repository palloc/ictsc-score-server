require "digest/sha2"

require "sinatra/activerecord_helpers"
require "sinatra/json_helpers"
require_relative "../services/account_service"

# ファイルアップロード
class AttachmentRoutes < Sinatra::Base
  helpers Sinatra::ActiveRecordHelpers
  helpers Sinatra::JSONHelpers
  helpers Sinatra::AccountServiceHelpers

  def uploads_dir
    @uploads_dir ||= Pathname(settings.root) + "../uploads/#{@attachment.id}/"
  end

  def file_path
    @file_path ||= (uploads_dir + @attachment.filename).to_s
  end

  before "/api/attachments*" do
    I18n.locale = :en if request.xhr?
  end

  get "/api/attachments" do
    @attachments = Attachment.readables(user: current_user)
    json @attachments
  end

  post "/api/attachments" do
    halt 403 if not Attachment.allowed_to_create_by?(current_user)

    file = params[:file] || {}

    @attrs = params_to_attributes_of(klass: Attachment)
    @attrs[:member_id] = current_user.id if (not is_admin?) || @attrs[:member_id].nil?
    @attrs[:filename]  = file[:filename]
    @attrs[:access_token] = SecureRandom.hex(32)

    @attachment = Attachment.new(@attrs)

    halt 400 if /(\/|\.\.)/ === file[:filename]

    if not @attachment.save
      status 400
      json @attachment.errors
    else
      # save file
      FileUtils.mkdir_p uploads_dir.to_s
      halt 400 unless file_path.start_with? uploads_dir.to_s

      File.write(file_path, file[:tempfile].read)

      status 201
      headers "Location" => to("/api/attachments/#{@attachment.id}")
      json @attachment, methods: [:url]
    end
  end

  before "/api/attachments/:id" do
    @attachment = Attachment.find_by(id: params[:id])
    halt 404 if not @attachment&.allowed?(by: current_user, method: request.request_method)
  end

  # IDからファイルの情報を取得
  get "/api/attachments/:id" do
    @attachment = Attachment.readables(user: current_user).find_by(id: params[:id])
    json @attachment
  end

  delete "/api/attachments/:id" do
    if @attachment.destroy
      status 204
      json status: "success"
    else
      status 500
      json status: "failed"
    end
  end

  # ファイルを取得
  get "/api/attachments/:id/:access_token" do
    @attachment = Attachment.find_by(id: params[:id])

    halt 403 if @attachment.access_token != params[:access_token]

    send_file file_path
  end

  def send_attachment
    filename = @attachment.filename

    if not response['Content-Type']
      content_type File.extname(filename), :default => 'application/octet-stream'
    end

    disposition = :attachment if filename.present?
    attachment(filename, disposition) if disposition
    headers['Content-Length'] = @attachment.data.bytesize

    @attachment.data
  end
end
