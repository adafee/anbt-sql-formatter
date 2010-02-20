# -*- coding: utf-8 -*-

require "pp"

require "anbt-sql-formatter/token"
require "anbt-sql-formatter/constants"
require "anbt-sql-formatter/helper"
require "anbt-sql-formatter/coarse-tokenizer"

class AnbtSql
  class Parser

    def initialize
      # 解析前の文字列
      @before = nil

      # 解析中の位置
      @pos = nil

      # 解析中の文字。
      @char = nil

      @token_pos = nil

      # ２文字からなる記号。
      # なお、|| は文字列結合にあたります。
      @two_character_symbol = [ "<>", "<=", ">=", "||" ]
    end


    ##
    # 2005.07.26:: Tosiki Iga \r も処理範囲に含める必要があります。
    # 2005.08.12:: Tosiki Iga 65535(もとは-1)はホワイトスペースとして扱うよう変更します。
    def space?(c)
      return c == ' ' ||
        c == "\t" ||
        c == "\n" ||
        c == "\r" ||
        c == 65535
    end


    ##
    # 文字として認識して妥当かどうかを判定します。
    # 全角文字なども文字として認識を許容するものと判断します。
    def letter?(c)
      return false if space?(c)
      return false if digit?(c)
      return false if symbol?(c)
      
      true
    end


    def digit?(c)
      return "0" <= c && c <= '9'
    end


    ##
    # "#" は文字列の一部とします
    # アンダースコアは記号とは扱いません
    # これ以降の文字の扱いは保留
    def symbol?(c)
      %w(" ? % & ' \( \) | * + , - . / : ; < = > ).include? c
      #"
    end


    ##
    # トークンを次に進めます。
    # 1. posを進める。
    # 2. sに結果を返す。
    # 3. typeにその種類を設定する。
    # 不正なSQLの場合、例外が発生します。
    # ここでは、文法チェックは行っていない点に注目してください。
    def next_sql_token
      $stderr.puts "next_token #{@pos} <#{@before}> #{@before.length}" if $DEBUG

      start_pos = @pos
      
      if @pos >= @before.length
        @pos += 1
        return nil
      end
      
      @char = @before.charAt(@pos)

      if space?(@char)
        workString = ""
        loop { 
          workString += @char

          @char = @before.charAt(@pos+1)
          if not space?(@char)
            @pos += 1
            return AnbtSql::Token.new(AnbtSql::TokenConstants::SPACE,
                                        workString, start_pos)
          end

          @pos += 1
          
          if @pos >= @before.length()
            return AnbtSql::Token.new(AnbtSql::TokenConstants::SPACE,
                                        workString, start_pos)
          end
        }

        
      elsif @char == ";"
        @pos += 1
        # 2005.07.26 Tosiki Iga セミコロンは終了扱いではないようにする。
        return AnbtSql::Token.new(AnbtSql::TokenConstants::SYMBOL,
                                    ";", start_pos)

      elsif digit?(@char)
        s = ""
        while (digit?(@char) || @char == '.') 
          # if (ch == '.') type = Token.REAL
          s += @char
          @pos += 1

          if (@pos >= @before.length) 
            # 長さを超えている場合には処理中断します。
            break
          end

          @char = @before.charAt(@pos)
        end
        return AnbtSql::Token.new(AnbtSql::TokenConstants::VALUE,
                                    s, start_pos)
        
        
      elsif letter?(@char)
        s = ""
        # 文字列中のドットについては、文字列と一体として考える。
        while (letter?(@char) || digit?(@char) || @char == '.') 
          s += @char
          @pos += 1
          if (@pos >= @before.length())
            break
          end

          @char = @before.charAt(@pos)
        end

        if AnbtSql::Constants::SQL_RESERVED_WORDS.map{|w| w.upcase }.include?(s.upcase)
          return AnbtSql::Token.new(AnbtSql::TokenConstants::KEYWORD,
                                      s, start_pos)
        end
        
        return AnbtSql::Token.new(AnbtSql::TokenConstants::NAME,
                                    s, start_pos)

      elsif symbol?(@char)
        s = "" + @char
        @pos += 1
        if (@pos >= @before.length()) 
          return AnbtSql::Token.new(AnbtSql::TokenConstants::SYMBOL,
                                      s, start_pos)
        end
        # ２文字の記号かどうか調べる
        ch2 = @before.charAt(@pos)
        #for (int i = 0; i < two_character_symbol.length; i++) {
        for i in 0...@two_character_symbol.length
          if (@two_character_symbol[i].charAt(0) == @char &&
              @two_character_symbol[i].charAt(1) == ch2)
            @pos += 1
            s += ch2
            break
          end
        end
        return AnbtSql::Token.new(AnbtSql::TokenConstants::SYMBOL,
                                    s, start_pos)


      else
        @pos += 1
        return AnbtSql::Token.new( AnbtSql::TokenConstants::UNKNOWN,
                                     "" + @char,
                                     start_pos )
      end
    end



    def prepare_tokens(coarse_tokens)
      @tokens = []

      pos = 0
      while pos < coarse_tokens.size
        coarse_token = coarse_tokens[pos]
        
        case coarse_token._type

        when :quote_single
          @tokens << AnbtSql::Token.new(AnbtSql::TokenConstants::VALUE,
                                          coarse_token.string)
        when :quote_double
          @tokens << AnbtSql::Token.new(AnbtSql::TokenConstants::NAME,
                                          coarse_token.string)
        when :comment_single
          @tokens << AnbtSql::Token.new(AnbtSql::TokenConstants::COMMENT,
                                          coarse_token.string.chomp)
        when :comment_multi
          @tokens << AnbtSql::Token.new(AnbtSql::TokenConstants::COMMENT,
                                          coarse_token.string)
        when :plain
          @before = coarse_token.string
          @pos = 0
          count = 0
          loop {
            token = next_sql_token()
            if $DEBUG
              pp "@" * 64, count, token, token.class
            end

            # if token._type == AnbtSql::TokenConstants::END_OF_SQL
            if token == nil
              break
            end

            @tokens.push token
            count += 1
          }
        end

        pos += 1
      end

      @tokens << AnbtSql::Token.new(AnbtSql::TokenConstants::END_OF_SQL,
                                      "")
    end


    def next_token
      @tokens[@token_pos]
    end


    ##
    # SQL文字列をトークンの配列に変換し返します。
    #
    # sql_str:: 変換前のSQL文
    def parse(sql_str)
      coarse_tokens = CoarseTokenizer.new.tokenize(sql_str)

      prepare_tokens(coarse_tokens)
      
      list = []
      count = 0
      @token_pos = 0
      loop {
        token = next_token()
        
        if $DEBUG
          pp "=" * 64, count, token, token.class
        end
        
        if token._type == AnbtSql::TokenConstants::END_OF_SQL
          break
        else
          ;
        end
        
        list.push token
        count += 1
        @token_pos += 1
      }

      list
    end
  end
end