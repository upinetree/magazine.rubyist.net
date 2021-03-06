#!/usr/bin/env ruby

##
## creatable - テーブル定義を読み込んで加工し、テンプレートで出力する
##

require 'yaml'
require 'erb'


##
## メインプログラムを表すクラス
##
## 使い方：
##  main = MainProgram.new()
##  output = main.execute(ARGV)
##  print output if output
##
class MainProgram

  def execute(argv=ARGV)
    # コマンドオプションの解析
    options, properties = _parse_options(ARGV)
    return usage() if options[:help]
    raise "テンプレートが指定されていません。" unless options[:template]

    # データファイルを読み込む。タブ文字は空白に展開する。
    s = ''
    while line = gets()
      s << line.gsub(/([^\t]{8})|([^\t]*)\t/n){[$+].pack("A8")}
    end
    doc = YAML.load(s)

    # 読み込んだデータを加工する
    manipulator = Manipulator.new(doc)
    manipulator.manipulate()

    # テンプレートを検索する
    t = options[:template]
    if test(?f, t)
      template = t
    elsif ENV['CREATABLE_PATH']
      path_list = ENV['CREATABLE_PATH'].split(File::PATH_SEPARATOR)
      template = path_list.find { |path| test(?f, "#{path}/#{t}") }
    end
    raise "'#{t}': テンプレートが見つかりません。" unless template
    
    # テンプレートを読み込んで出力を生成する
    s = File.read(template)
    trim_mode = '>'        # '%>' で終わる行では改行を出力しない
    erb = ERB.new(s, $SAFE, trim_mode)
    if options[:multiple]  # 複数ファイルへ出力
      doc['tables'].each do |table|
        context = { 'table' => table, 'properties' => properties }
        output = _eval_erb(erb, context)
        filename = context[:output_filename]   # 出力ファイル名
        filename = options[:directory] + "/" + filename if options[:directory]
        File.open(filename, 'w') do |f|
          f.write(output)
          $stderr.puts "generated: #{filename}"
        end if filename
      end
      output = nil
    else                   # 標準出力へ出力
      context = { 'tables' => doc['tables'], 'properties' => properties }
      output = _eval_erb(erb, context)
    end
    return output
  end

  private

  ## テンプレートを適用する。
  def _eval_erb(__erb, context)
    # このようにERB#result()だけを実行するメソッドを用意すると、
    # 必要な変数（この場合ならcontext）だけをテンプレートに渡し、
    # 不必要なローカル変数は渡さなくてすむようになる。
    return __erb.result(binding())
  end

  ## ヘルプメッセージ
  def usage()
     s = ''
     s << "Usage: ruby creatable.rb [-h] [-m] -f template datafile.yaml [...]\n"
     s << "  -h          : ヘルプ\n"
     s << "  -m          : multiple output file\n"
     s << "  -f template : テンプレートのファイル名\n"
     return s
  end

  ## コマンドオプションおよびテンプレートプロパティを解析する
  def _parse_options(argv)
    options = {}
    properties = {}
    while argv[0] && argv[0][0] == ?-
      opt = argv.shift
      if opt =~ /^--(.*)/
        # テンプレートプロパティ
        param_str = $1
        if param_str =~ /\A([-\w]+)=(.*)/
          key, value = $1, $2
        else
          key, value = param_str, true
        end
        properties[key] = value
      else
        # コマンドオプション
        case opt
        when '-h'      # ヘルプ
          options[:help] = true
        when '-f'      # テンプレート名
          arg = argv.shift
          raise "-f: テンプレート名を指定してください。" unless arg
          options[:template] = arg
        when '-m'   # テーブルごとの出力ファイル
          options[:multiple] = true
        when '-d'   # 出力先ディレクトリ
          arg = argv.shift
          raise "-d: ディレクトリ名を指定してください。" unless arg
          options[:directory] = arg
        else
          raise "#{opt}: コマンドオプションが間違ってます。"
        end
      end
    end
    return options, properties
  end

end


##
## 定義ファイルから読み込んだデータをチェックし、加工するクラス
##
## 使い方：
##   doc = YAML.load(file)
##   manipulator = Manipulator.new()
##   manipulator.manipulate(doc)
##
class Manipulator

  def initialize(doc)
    @defaults = doc['defaults'] || {}
    @tables   = doc['tables']   || []
  end

  ## 定義ファイルから読み込んだデータを操作する
  def manipulate()
    
    # 「カラム名→カラム定義」の Hash を作成する
    default_columns = {}
    @defaults['columns'].each do |column|
      colname = column['name']
      raise "カラム名がありません。" unless colname
      raise "#{colname}: カラム名が重複しています。" if default_columns[colname]
      default_columns[colname] = column
    end if @defaults['columns']

    # テーブルのカラムをチェックし値を設定する
    tablenames = {}
    @tables.each do |table|
      tblname = table['name']
      raise "テーブル名がありません。" unless tblname
      raise "#{tblname}: テーブル名が重複しています。" if tablenames[tblname]
      tablenames[tblname] = true
      colnames = {}
      table['columns'].each do |column|
        colname = column['name']
        raise "#{tblname}: カラム名がありません。" unless colname
        raise "#{tblname}.#{colname}: カラム名が重複しています。" if colnames[colname]
        colnames[colname] = true
        # カラムのデフォルト値を設定
        default_column = default_columns[colname]
        default_column.each do |key, val|
          column[key] = val unless column.key?(key)
        end if default_column
        # カラムからテーブルへのリンクを設定
        column['table'] = table
        # 外部キーで参照しているカラムの、データ型とカラム幅をコピーする
        if (ref_column = column['ref']) != nil
          column['type']    = ref_column['type']
          column['width'] ||= ref_column['width']  if ref_column.key?('width')
        end
      end if table['columns']
    end
  end

end


## メインプログラムを実行
main = MainProgram.new
output = main.execute(ARGV)
print output if output
