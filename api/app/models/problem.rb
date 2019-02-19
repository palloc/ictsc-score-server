class Problem < ApplicationRecord
  validates :title,     presence: true
  validates :text,      presence: true, length: { maximum: 4095 }
  validates :creator,   presence: true
  validates :order,     presence: true
  validates :reference_point, presence: true
  validates :perfect_point,   presence: true
  validates :secret_text,     presence: false, allow_nil: false, length: { maximum: 4095 } # allow empty, reject nil
  validates :team_private,    inclusion: { in: [true, false] }
  validates :problem_must_solve_before, presence: false

  has_many :answers,  dependent: :destroy
  has_many :comments, dependent: :destroy, as: :commentable
  has_many :issues,   dependent: :destroy
  has_many :first_correct_answer, dependent: :destroy
  has_many :next_problems, class_name: to_s, foreign_key: 'problem_must_solve_before_id'
  has_and_belongs_to_many :problem_groups, dependent: :nullify
  belongs_to :problem_must_solve_before, class_name: to_s
  belongs_to :creator, foreign_key: 'creator_id', class_name: 'Member'

  # method: POST
  def self.allowed_to_create_by?(user = nil, action: '')
    case user&.role_id
    when ROLE_ID[:admin], ROLE_ID[:writer]
      true
    else
      false
    end
  end

  def readable?(by: nil, action: '')
    self.class.readables(user: by, action: action).exists?(id: id)
  end

  # method: GET, PUT, PATCH, DELETE
  def allowed?(by: nil, method:, action: '')
    return readable?(by: by, action: action) if method == 'GET'

    case by&.role_id
    when ROLE_ID[:admin]
      true
    when ROLE_ID[:writer]
      creator_id == by.id
    else
      false
    end
  end

  # 権限によって許可するパラメータを変える
  def self.allowed_nested_params(user:)
    base_params = %w(answers answers-score answers-team issues issues-comments comments problem_groups)
    case user&.role_id
    when ROLE_ID[:admin], ROLE_ID[:writer], ROLE_ID[:viewer]
      base_params + %w(creator)
    when ROLE_ID[:participant]
      base_params
    else
      %w()
    end
  end

  def self.readable_columns(user:, action: '', reference_keys: true)
    case user&.role_id
    when ROLE_ID[:admin], ROLE_ID[:writer]
      all_column_names(reference_keys: reference_keys)
    when ROLE_ID[:viewer]
      all_column_names(reference_keys: reference_keys) - %w(secret_text)
    when ROLE_ID[:participant]
      case action
      when 'not_opened'
        # 未開放問題の閲覧可能情報
        %w(id team_private order problem_must_solve_before_id created_at updated_at)
      else
        all_column_names(reference_keys: reference_keys) - %w(creator_id reference_point secret_text)
      end
    else
      []
    end
  end

  scope :filter_columns, lambda {|user:, action: ''|
    cols = readable_columns(user: user, action: action, reference_keys: false)
    next none if cols.empty?

    select(*cols)
  }

  def self.readable_records(user:, action: '')
    case user&.role_id
    when ROLE_ID[:admin], ROLE_ID[:viewer]
      all
    when ROLE_ID[:writer]
      return all if action.empty?
      return where(creator: user) if action == 'problems_comments'
      none
    when ->(role_id) { role_id == ROLE_ID[:participant] || user&.team.present? }
      return none unless Config.in_competition_time?

      case action
      when 'not_opened'
        # 未開放問題
        where.not(id: opened(user: user).ids)
      else
        opened(user: user)
      end
    else
      none
    end
  end

  # method: GET
  scope :readables, lambda {|user:, action: ''|
    readable_records(user: user, action: action)
      .filter_columns(user: user, action: action)
  }

  def readable_teams
    Team.select do |team|
      # 適当にチームからユーザを取得してもいいが、想定外の動作をする可能性があるからダミーユーザーを使う
      readable?(by: Member.new(role: Role.participant, team: team))
    end
  end

  class << self
    # 突破チーム数を返す
    # idが指定されると単一の値を返す
    # 返すハッシュのデフォルト値は0
    def solved_teams_counts(user:, id: nil)
      rel = id.nil? ? FirstCorrectAnswer.all : FirstCorrectAnswer.where(problem_id: id)

      counts = rel
        .readables(user: user, action: 'all_opened')
        .group(:problem_id)
        .count(:team_id) # readables内でselectしてるからカラムの指定が必要

      counts.default = 0

      id.nil? ? counts : counts[id]
    end

    private

    # userが閲覧できる問題一覧
    def opened(user:)
      return all if Config.problem_open_all_at <= DateTime.now

      all_team_fcas = FirstCorrectAnswer.readables(user: user, action: 'all_opened')
      my_team_fcas = all_team_fcas.where(team: user.team)

      # 依存問題がない
      # 自チームが依存問題を解決
      # 他チームが依存問題を解決していてteam_private == false
      where(problem_must_solve_before_id: nil)
        .or(where(problem_must_solve_before_id: my_team_fcas.pluck(:problem_id)))
        .or(where(problem_must_solve_before_id: all_team_fcas.pluck(:problem_id), team_private: false))
    end
  end
end