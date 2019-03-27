require 'sqlite3'
require 'singleton'
require 'faker'
require 'byebug'

class SuperModel
  def save
    all_columns = self.instance_variables
    if self.id
      self.update
    else
      QuestionsDatabase.instance.execute(<<-SQL, self.fname, self.lname)
        INSERT INTO
          users (fname, lname)
        VALUES
          (?, ?)
      SQL

      self.id = QuestionsDatabase.instance.last_insert_row_id
    end
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL, self.fname, self.lname, self.id)
      UPDATE
        users
      SET
        fname = ?, lname = ?
      WHERE
        id = ?
    SQL
  end
end

class QuestionsDatabase < SQLite3::Database
  include Singleton  

  def initialize
    super('questions.db')
    self.type_translation = true
    self.results_as_hash = true
  end

  def self.seed_users
    1000.times do
      User.new('fname' => Faker::Name.first_name, 'lname' => Faker::Name.last_name).save
    end
  end

  def self.seed_questions
    1000.times do
      Question.new('title' => Faker::Lorem.sentence, 'body' => Faker::Lorem.paragraph, 'user_id' => rand(1000)).save
    end
  end

  def self.seed_follows
    1000.times do
      QuestionFollow.new('question_id' => rand(1000), 'user_id' => rand(1000)).save
    end
  end

  def self.seed_likes
    1000.times do
      QuestionLike.new('question_id' => rand(1000), 'user_id' => rand(1000)).save
    end
  end

  def self.seed_parent_replies
    500.times do
      Reply.new('body' => Faker::Lorem.paragraph, 'question_id' => rand(1000), 'user_id' => rand(1000)).save
    end
  end

  def self.seed_children_replies
    1000.times do
      parent_id = rand(1..500)
      parent = Reply.find_by_id(parent_id)
      parent_question_id = parent.question_id
      faker_paragraph = Faker::Lorem.paragraph
      options_hash = {'body' => faker_paragraph, 'question_id' => parent_question_id, 'user_id' => rand(1000), 'parent_id' => parent_id}
      Reply.new(options_hash).save
    end
  end

  def self.seed_grandchildren_replies
    1000.times do
      parent_id = rand(501..1500)
      parent = Reply.find_by_id(parent_id)
      parent_question_id = parent.question_id
      options_hash = {'body' => Faker::Lorem.paragraph, 'question_id' => parent_question_id, 'user_id' => rand(1000), 'parent_id' => parent_id}
      Reply.new(options_hash).save
    end
  end

end


class User
  attr_accessor :id, :fname, :lname

  def self.all
    data = QuestionsDatabase.instance.execute("SELECT * FROM users")
    data.map { |datum| User.new(datum) }
  end

  def self.find_by_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM users WHERE id = #{id}")
    User.new(data.first)
  end

  def self.find_by_name(firstname, lastname)
    data = QuestionsDatabase.instance.execute(<<-SQL, firstname, lastname)
      SELECT *
      FROM users
      WHERE fname = ? AND lname = ?
      SQL
    User.new(data.first)
  end

  def self.change_all(column, new_value)
    all_users = User.all
    all_users.each do |user|
      user.instance_variable_set(column, new_value)
      user.update
    end
  end

  def initialize(options)
    @id = options['id']
    @fname = options['fname']
    @lname = options['lname']
  end

  def save
    if self.id
      self.update
    else
      QuestionsDatabase.instance.execute(<<-SQL, self.fname, self.lname)
        INSERT INTO
          users (fname, lname)
        VALUES
          (?, ?)
      SQL

      self.id = QuestionsDatabase.instance.last_insert_row_id
    end
  end

  def update
    QuestionsDatabase.instance.execute(<<-SQL, self.fname, self.lname, self.id)
      UPDATE
        users
      SET
        fname = ?, lname = ?
      WHERE
        id = ?
    SQL
  end


  def authored_questions
    Question.find_by_author_id(self.id)
  end

  def authored_replies
    Reply.find_by_user_id(self.id)
  end

  def followed_questions
    QuestionFollow.followed_questions_for_user_id(self.id)
  end

  def liked_questions
    QuestionLike.liked_questions_for_user_id(self.id)
  end

  def average_karma
    QuestionsDatabase.instance.execute(<<-SQL, self.id)
      SELECT
        CAST(COUNT(*) AS FLOAT)/COUNT(DISTINCT Q.id) AS avg_karma
      FROM
        questions Q
      LEFT OUTER JOIN
        question_likes QL ON Q.id = QL.question_id
      WHERE
        Q.user_id = ?
    SQL
  end
end

class Question
  attr_accessor :id, :title, :body, :user_id

  def self.all
    data = QuestionsDatabase.instance.execute("SELECT * FROM questions")
    data.map { |datum| Question.new(datum) }
  end

  def self.find_by_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM questions WHERE id = #{id}")
    Question.new(data.first)
  end

  def self.change_all(column, new_value)
    all_questions = Question.all
    all_questions.each do |question|
      question.instance_variable_set(column, new_value)
      question.update
    end
  end

  def self.find_by_author_id(author_id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM questions WHERE user_id = #{author_id}")
    data.map { |question| Question.new(question) }
  end

  def self.most_followed(n)
    QuestionFollow.most_followed_questions(n)
  end

  def self.most_liked(n)
    QuestionLike.most_liked_questions(n)
  end

  def initialize(options)
    @id = options['id']
    @title = options['title']
    @body = options['body']
    @user_id = options['user_id']
  end

  def save
    raise "#{self} already in database" if self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.title, self.body, self.user_id)
      INSERT INTO
        questions (title, body, user_id)
      VALUES
        (?, ?, ?)
    SQL

    self.id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    raise "#{self} not in database" unless self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.title, self.body, self.user_id, self.id)
      UPDATE
        questions
      SET
        title = ?, body = ?, user_id = ?
      WHERE
        id = ?
    SQL
  end

  def author
    User.find_by_id(self.user_id)
  end

  def replies
    Reply.find_by_question_id(self.id)
  end

  def followers 
    QuestionFollow.followers_for_question_id(self.id)
  end

  def likers
    QuestionLike.likers_for_question_id(self.id)
  end

  def num_likes
    QuestionLike.num_likes_for_question_id(self.id)
  end

end

class QuestionFollow
  attr_accessor :id, :question_id, :user_id

  def self.all
    data = QuestionsDatabase.instance.execute("SELECT * FROM question_follows")
    data.map { |datum| QuestionFollow.new(datum) }
  end

  def self.find_by_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM question_follows WHERE id = #{id}")
    QuestionFollow.new(data.first)
  end

  def self.change_all(column, new_value)
    all_follows = QuestionFollow.all
    all_follows.each do |follow|
      follow.instance_variable_set(column, new_value)
      follow.update
    end
  end

  def self.followers_for_question_id(question_id)
    data = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT 
        U.id,
        U.fname,
        U.lname
      FROM
        question_follows
      JOIN 
        users U ON user_id = U.id
      WHERE
        question_id = ?
    SQL

    data.map { |datum| User.new(datum) }
  end

  def self.followed_questions_for_user_id(user_id)
    data = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        Q.id,
        Q.title,
        Q.body,
        Q.user_id
      FROM
        questions Q
      JOIN
        question_follows QF ON Q.id = QF.question_id
      WHERE
        QF.user_id = ?
    SQL

    data.map { |datum| Question.new(datum) }
  end

  def self.most_followed_questions(n)
    data = QuestionsDatabase.instance.execute(<<-SQL, n)
      SELECT
        Q.id,
        Q.title,
        Q.body,
        Q.user_id
      FROM
        questions Q
      JOIN
        question_follows QF ON Q.id = QF.question_id
      GROUP BY
        Q.id
      ORDER BY
        COUNT(QF.id) DESC
      LIMIT
        ?
    SQL
    data.map { |datum| Question.new(datum) }
  end

  def initialize(options)
    @id = options['id']
    @question_id = options['question_id']
    @user_id = options['user_id']
  end

  def save
    raise "#{self} already in database" if self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.question_id, self.user_id)
      INSERT INTO
        question_follows (question_id, user_id)
      VALUES
        (?, ?)
    SQL

    self.id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    raise "#{self} not in database" unless self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.question_id, self.user_id, self.id)
      UPDATE
        question_follows
      SET
        question_id = ?, user_id = ?
      WHERE
        id = ?
    SQL
  end
end

class Reply
  attr_accessor :id, :body, :question_id, :user_id, :parent_id

  def self.all
    data = QuestionsDatabase.instance.execute("SELECT * FROM replies")
    data.map { |datum| Reply.new(datum) }
  end

  def self.find_by_user_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM replies WHERE user_id = #{id}")
    data.map { |datum| Reply.new(datum) }
  end

  def self.find_by_question_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM replies WHERE question_id = #{id}")
    raise "No reply to this question" if data.empty?

    data.map { |datum| Reply.new(datum) }
  end

  def self.find_by_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM replies WHERE id = #{id}")
    Reply.new(data.first)
  end

  def self.change_all(column, new_value)
    all_replies = Reply.all
    all_replies.each do |reply|
      reply.instance_variable_set(column, new_value)
      reply.update
    end
  end

  def initialize(options)
    @id = options['id']
    @body = options['body']
    @question_id = options['question_id']
    @user_id = options['user_id']
    @parent_id = options['parent_id']
  end

  def save
    raise "#{self} already in database" if self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.body, self.question_id, self.user_id, self.parent_id)
      INSERT INTO
        replies (body, question_id, user_id, parent_id)
      VALUES
        (?, ?, ?, ?)
    SQL

    self.id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    raise "#{self} not in database" unless self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.body, self.question_id, self.user_id, self.parent_id, self.id)
      UPDATE
        replies
      SET
        body = ?, question_id = ?, user_id = ?, parent_id = ?
      WHERE
        id = ?
    SQL
  end

  def author
    User.find_by_id(self.user_id)
  end

  def question
    Question.find_by_id(self.question_id)
  end

  def parent_reply
    if self.parent_id
      Reply.find_by_id(self.parent_id)
    else
      raise ArgumentError.new("I am a parent!")
    end
  end

  def child_replies 
    data = QuestionsDatabase.instance.execute("SELECT * FROM replies WHERE parent_id = #{id}")
    data.map { |datum| Reply.new(datum) }
  end
end

class QuestionLike
  attr_accessor :id, :question_id, :user_id

  def self.all
    data = QuestionsDatabase.instance.execute("SELECT * FROM question_likes")
    data.map { |datum| QuestionLike.new(datum) }
  end

  def self.find_by_id(id)
    data = QuestionsDatabase.instance.execute("SELECT * FROM question_likes WHERE id = #{id}")
    QuestionLike.new(data.first)
  end

  def self.change_all(column, new_value)
    all_likes = QuestionLike.all
    all_likes.each do |like|
      like.instance_variable_set(column, new_value)
      like.update
    end
  end

  def self.likers_for_question_id(question_id)
    data = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        U.id,
        U.fname,
        U.lname
      FROM
        question_likes QL
      JOIN
        users U ON U.id = QL.user_id
      WHERE
        QL.id = ?
    SQL

    data.map { |datum| User.new(datum) }  
  end

  def self.num_likes_for_question_id(question_id)
    data = QuestionsDatabase.instance.execute(<<-SQL, question_id)
      SELECT
        COUNT(*) AS num_likes
      FROM
        question_likes QL
      JOIN
        users U ON U.id = QL.user_id
      WHERE
        QL.id = ?
    SQL
  
    data.first.values[0]
  end

  def self.liked_questions_for_user_id(user_id)
    data = QuestionsDatabase.instance.execute(<<-SQL, user_id)
      SELECT
        Q.id,
        Q.title,
        Q.body,
        Q.user_id
      FROM
        questions Q
      JOIN
        question_likes QL ON Q.id = QL.question_id
      WHERE
        QL.user_id = ?
    SQL

    data.map { |datum| Question.new(datum) }
  end

  def self.most_liked_questions(n)
    data = QuestionsDatabase.instance.execute(<<-SQL, n)
      SELECT
        Q.id,
        Q.title,
        Q.body,
        Q.user_id
      FROM
        questions Q
      JOIN
        question_likes QL ON Q.id = QL.question_id
      GROUP BY
        Q.id
      ORDER BY
        COUNT(*) DESC
      LIMIT
        ?
    SQL

    data.map { |datum| Question.new(datum) }
  end

  def initialize(options)
    @id = options['id']
    @question_id = options['question_id']
    @user_id = options['user_id']
  end

  def save
    raise "#{self} already in database" if self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.question_id, self.user_id)
      INSERT INTO
        question_likes (question_id, user_id)
      VALUES
        (?, ?)
    SQL

    self.id = QuestionsDatabase.instance.last_insert_row_id
  end

  def update
    raise "#{self} not in database" unless self.id
    QuestionsDatabase.instance.execute(<<-SQL, self.question_id, self.user_id, self.id)
      UPDATE
        question_likes
      SET
        question_id = ?, user_id = ?
      WHERE
        id = ?
    SQL
  end
end