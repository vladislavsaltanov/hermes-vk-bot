# frozen_string_literal: true

require 'sqlite3'

class ChatSession
  class << self
    attr_writer :db_path

    ##
    # The `db_path` function returns the database path from the environment variable `DB_PATH` or
    # defaults to 'bot.db'.
    def db_path
      @db_path ||= ENV.fetch('DB_PATH', 'bot.db')
    end

    ##
    # The `setup_db` function creates two tables, `sessions` and `messages`, in a database if they do
    # not already exist.
    def setup_db
      with_db do |db|
        # The `db.execute(<<~SQL)` syntax in Ruby is a way to write multi-line strings in a cleaner
        # and more readable format.
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now'))
          )
        SQL
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL
          )
        SQL
      end
    end

    ##
    # The `create` function inserts a new record into the sessions table with the given name and
    # returns a new object with the generated id and name.
    # Args:
    #   name: The `create` method takes a `name` parameter as input. This parameter is used to insert
    # a new record into the `sessions` table in the database with the provided name value.
    def create(name)
      id = nil
      with_db do |db|
        db.execute('INSERT INTO sessions (name) VALUES (?)', [name])
        id = db.last_insert_row_id
      end
      new(id, name)
    end

    ##
    # This Ruby function retrieves all rows from a database table called "sessions" and returns them
    # as objects.
    def all
      rows = nil
      with_db { |db| rows = db.execute('SELECT id, name, created_at FROM sessions ORDER BY created_at DESC') }
      rows.map { |r| new(r[0], r[1], r[2]) }
    end

    ##
    # This Ruby function finds a session by its ID in a database table and returns the corresponding
    # row as an object.
    #
    # Args:
    #   id: The `find` method takes an `id` parameter, which is used to search for a session in the
    # database based on the provided `id`. The method retrieves the session's `id`, `name`, and
    # `created_at` values from the database and returns a new object with these values if
    def find(id)
      row = nil
      with_db { |db| row = db.get_first_row('SELECT id, name, created_at FROM sessions WHERE id = ?', [id]) }
      row ? new(row[0], row[1], row[2]) : nil
    end

    ##
    # The `with_db` function opens a SQLite3 database connection, yields it to a block of code, and
    # ensures the database connection is closed after the block execution.
    def with_db
      db = SQLite3::Database.new(db_path)
      yield db
    ensure
      db&.close
    end
  end

  # The `attr_reader :id, :name, :created_at` line in the `ChatSession` class is creating getter
  # methods for the instance variables `@id`, `@name`, and `@created_at`.
  attr_reader :id, :name, :created_at

  ##
  # The `initialize` function initializes a new instance of the `ChatSession` class with the given
  # id, name, and created_at values.
  def initialize(id, name, created_at = nil)
    @id = id
    @name = name
    @created_at = created_at
  end

  ##
  # The `add_message` function inserts a new message into a database table with the provided role and
  # content values.
  #
  # Args:
  #   role: The `role` parameter in the `add_message` method represents the role of the user who is
  # sending the message. It could be a string indicating the role such as "admin", "user",
  # "moderator", etc.
  #   content: The `content` parameter in the `add_message` method is the actual message content that
  # you want to insert into the database. It could be a text message, a notification, or any other
  # type of content that you want to associate with a specific role in the database.
  def add_message(role, content)
    self.class.with_db do |db|
      db.execute('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)', [@id, role, content])
    end
  end

  ##
  # This Ruby function retrieves messages from a database based on a session ID and returns them as an
  # array of hashes containing role and content.
  def messages
    rows = nil
    self.class.with_db do |db|
      rows = db.execute('SELECT role, content FROM messages WHERE session_id = ? ORDER BY id', [@id])
    end
    # The `rows.map { |r| { role: r[0], content: r[1] } }` line is iterating over each row in the
    # `rows` array, which contains the results of a database query. For each row `r`, it creates a new
    # hash with keys `role` and `content`, where the values are extracted from the elements of the row
    # `r`.
    rows.map { |r| { role: r[0], content: r[1] } }
  end

  ##
  # This Ruby function clears all messages associated with a specific session ID from the database.
  def clear_messages
    self.class.with_db { |db| db.execute('DELETE FROM messages WHERE session_id = ?', [@id]) }
  end
end
