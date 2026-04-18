# frozen_string_literal: true

require 'sqlite3'

class ChatSession
  class << self
    attr_writer :db_path

    def db_path
      @db_path ||= ENV.fetch('DB_PATH', 'bot.db')
    end

    def setup_db
      with_db do |db|
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

    def create(name)
      id = nil
      with_db do |db|
        db.execute('INSERT INTO sessions (name) VALUES (?)', [name])
        id = db.last_insert_row_id
      end
      new(id, name)
    end

    def all
      rows = nil
      with_db { |db| rows = db.execute('SELECT id, name, created_at FROM sessions ORDER BY created_at DESC') }
      rows.map { |r| new(r[0], r[1], r[2]) }
    end

    def find(id)
      row = nil
      with_db { |db| row = db.get_first_row('SELECT id, name, created_at FROM sessions WHERE id = ?', [id]) }
      row ? new(row[0], row[1], row[2]) : nil
    end

    def with_db
      db = SQLite3::Database.new(db_path)
      yield db
    ensure
      db&.close
    end
  end

  attr_reader :id, :name, :created_at

  def initialize(id, name, created_at = nil)
    @id = id
    @name = name
    @created_at = created_at
  end

  def add_message(role, content)
    self.class.with_db do |db|
      db.execute('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)', [@id, role, content])
    end
  end

  def messages
    rows = nil
    self.class.with_db do |db|
      rows = db.execute('SELECT role, content FROM messages WHERE session_id = ? ORDER BY id', [@id])
    end
    rows.map { |r| { role: r[0], content: r[1] } }
  end

  def clear_messages
    self.class.with_db { |db| db.execute('DELETE FROM messages WHERE session_id = ?', [@id]) }
  end
end
