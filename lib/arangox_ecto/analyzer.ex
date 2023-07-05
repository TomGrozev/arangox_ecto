defmodule ArangoXEcto.Analyzer do
  @moduledoc """
  Defines an analyzer for use in views

  Since analyzer defintions are short and you may have many of them, you can just define multiple
  analyzer modules in one file, e.g. named analyzers.ex.

  ## Example

      defmodule MyApp.Analyzers do
        use ArangoXEcto.Analyzer

        norm :norm_en, [:frequency, :norm, :position], %{
          locale: "en",
          accent: false,
          case: :lower
        }

        # this exists by default but is just used as an example
        text :text_en, [:frequency, :norm, :position], %{
          locale: "en",
          accent: false,
          stemming: true,
          case: :lower
        }

        # Needed to compile the analyzers
        build()
      end

  ## Features

  The following are the features available to all the analyzers. Some analyzers and functions need certin features enabled,
  refer to the [ArangoDB docs](https://www.arangodb.com/docs/stable/analyzers.html#analyzer-features) for more info.

      * `:frequency` - (boolean) - track how often a term occurs.
      * `:norm` - (boolean) - calculate and store the field normalization factor that is used to score fairer if the same term is repeated, reducing its importance.
      * `:position` - (boolean) - enumerate the tokens for position-dependent queries.
  """
  @moduledoc since: "1.3.0"

  @doc false
  defmacro __using__(_) do
    quote do
      import ArangoXEcto.Analyzer

      Module.register_attribute(__MODULE__, :analyzers, accumulate: true)

      Module.put_attribute(__MODULE__, :pipeline, nil)
    end
  end

  @doc """
  Compiles analyzers
  """
  defmacro build do
    quote do
      def __analyzers__, do: @analyzers
    end
  end

  @doc """
  Defines an identity type analyzer.

  An Analyzer applying the identity transformation, i.e. returning the input unmodified.

  Refer to the [ArangoDB Identity Docs](https://www.arangodb.com/docs/stable/analyzers.html#identity) for more info.

  This does not accept any properties.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
  """
  defmacro identity(name, features) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      analyzer = %{
        name: name,
        type: :identity,
        features: features
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a delimiter type analyzer.

  An Analyzer capable of breaking up delimited text into tokens as per RFC 4180 (without starting new records on newlines).

  Refer to the [ArangoDB Delimiter Docs](https://www.arangodb.com/docs/stable/analyzers.html#delimiter) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `delimiter` - (string) - the delimiting character(s). The whole string is considered as one delimiter.
  """
  defmacro delimiter(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [:delimiter])

      analyzer = %{
        name: name,
        type: :delimiter,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a stem type analyzer.

  An Analyzer capable of stemming the text, treated as a single token, for supported languages.

  Refer to the [ArangoDB Stem Docs](https://www.arangodb.com/docs/stable/analyzers.html#stem) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `locale` - (string) - a locale in the format language[_COUNTRY] (square brackets denote optional parts), e.g. "de" or "en_US".
  """
  defmacro stem(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties = ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [:locale])

      analyzer = %{
        name: name,
        type: :stem,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a norm type analyzer.

  An Analyzer capable of normalizing the text, treated as a single token, i.e. case conversion and accent removal.

  Refer to the [ArangoDB Norm Docs](https://www.arangodb.com/docs/stable/analyzers.html#norm) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `locale` - (string) - a locale in the format language[_COUNTRY] (square brackets denote optional parts), e.g. "de" or "en_US".
      * `accent` - (boolean) - whether to preserve accented characters or convert them to the base characters.
      * `case` - (atom) - option of how to store case
        * `:lower` - to convert to all lower-case characters
        * `:upper` - to convert to all upper-case characters
        * `:none` - to not change character case (default)
  """
  defmacro norm(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :locale,
          :accent,
          :case
        ])

      analyzer = %{
        name: name,
        type: :norm,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a ngram type analyzer.

  An Analyzer capable of producing n-grams from a specified input in a range of min..max (inclusive). Can optionally preserve the original input.

  Refer to the [ArangoDB NGram Docs](https://www.arangodb.com/docs/stable/analyzers.html#ngram) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `min` - (integer) - minimum n-gram length.
      * `max` - (integer) - maximum n-gram length.
      * `preserveOriginal` - (boolean) - whether to include the original value or just use the min & max values.
      * `startMarker` - (string) - this value will be prepended to n-grams which include the beginning of the input.
      * `endMarker` - (string) - this value will be appended to n-grams which include the end of the input.
      * `streamType` - (atom) - type of the input stream.
        * `:binary` - one byte is considered as one character (default).
        * `:utf8` - one Unicode codepoint is treated as one character.
  """
  defmacro ngram(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :min,
          :max,
          :preserveOriginal,
          :startMarker,
          :endMarker,
          :streamType
        ])

      analyzer = %{
        name: name,
        type: :ngram,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a text type analyzer.

  An Analyzer capable of breaking up strings into individual words while also optionally filtering out stop-words,
  extracting word stems, applying case conversion and accent removal.

  Refer to the [ArangoDB Text Docs](https://www.arangodb.com/docs/stable/analyzers.html#text) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `locale` - (string) - a locale in the format language[_COUNTRY] (square brackets denote optional parts), e.g. "de" or "en_US".
      * `accent` - (boolean) - whether to preserve accented characters or convert them to the base characters.
      * `case` - (string) - option of how to store case
        * `:lower` - to convert to all lower-case characters
        * `:upper` - to convert to all upper-case characters
        * `:none` - to not change character case (default)
      * `stemming` - (boolean) - whether to apply stemming on returned words or leave as-is
      * `edgeNgram` - (map) - if present, then edge n-grams are generated for each token (word). 
        * `min` - (integer) - minimum n-gram length.
        * `max` - (integer) - maximum n-gram length.
        * `preserveOriginal` - (boolean) - whether to include the original value or just use the min & max values.
      * `stopwords` - (list of strings) - a list of strings with words to omit from result.
      * `stopwordsPath` - (string) - path with a language sub-directory (e.g. en for a locale en_US) containing files with words to omit.
  """
  defmacro text(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :locale,
          :accent,
          :case,
          :stemming,
          :edgeNgram,
          :stopwords,
          :stopwordsPath
        ])

      analyzer = %{
        name: name,
        type: :text,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a collation type analyzer.

  An Analyzer capable of converting the input into a set of language-specific tokens. This makes comparisons follow the
  rules of the respective language, most notable in range queries against Views.

  Refer to the [ArangoDB Collation Docs](https://www.arangodb.com/docs/stable/analyzers.html#collation) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `locale` - (string) - a locale in the format language[_COUNTRY] (square brackets denote optional parts), e.g. "de" or "en_US".
  """
  defmacro collation(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties = ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [:locale])

      analyzer = %{
        name: name,
        type: :collation,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines an aql type analyzer.

  An Analyzer capable of running a restricted AQL query to perform data manipulation / filtering.

  Refer to the [ArangoDB AQL Docs](https://www.arangodb.com/docs/stable/analyzers.html#aql) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `queryString` - (string) - AQL query to be executed.
      * `collapsePositions` - (boolean) - whether to set the position to 0 for all members of the query result array (true) or
        set the position corresponding to the index of the result array member (false).
      * `keepNull` - (boolean) - either treat treat null like an empty string or discard null.
      * `batchSize` - (integer) - number between 1 and 1000 (default = 1) that determines the batch size for reading data from the query.
      * `memoryLimit` - (integer) - memory limit for query execution in bytes. (default is 1048576 = 1Mb) Maximum is 33554432U (32Mb).
      * `returnType` - (string) - data type of the returned tokens.
        `:string` - convert emitted tokens to strings.
        `:number` - convert emitted tokens to numbers.
        `:bool` - convert emitted tokens to booleans.
  """
  defmacro aql(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :queryString,
          :collapsePositions,
          :keepNull,
          :batchSize,
          :memoryLimit,
          :returnType
        ])

      analyzer = %{
        name: name,
        type: :aql,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a pipeline type analyzer.

  An Analyzer capable of chaining effects of multiple Analyzers into one. The pipeline is a list of Analyzers, where the output
  of an Analyzer is passed to the next for further processing. The final token value is determined by last Analyzer in the pipeline.

  Refer to the [ArangoDB Pipeline Docs](https://www.arangodb.com/docs/stable/analyzers.html#pipeline) for more info.

  > ### Note {: .info}
  >
  > Features are only required on the pipeline and not on the individual analyzers within. Any features on sub analyzers will be ignored if supplied.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `analyzers` - a block with other analyzers

  ## Example

      pipeline :my_pipeline, [:frequency, :norm, :position] do
        norm "norm_en",  %{
          locale: "en",
          accent: false,
          case: :lower
        }

        text "text_en", %{
          locale: "en",
          accent: false,
          stemming: true,
          case: :lower
        }
      end
  """
  defmacro pipeline(name, features, block) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      Module.put_attribute(__MODULE__, :pipeline, [])

      try do
        unquote(block)
      after
        :ok
      end

      Module.put_attribute(__MODULE__, :analyzers, %{
        name: name,
        type: :pipeline,
        features: features,
        properties: %{pipeline: Module.get_attribute(__MODULE__, :pipeline)}
      })

      Module.put_attribute(__MODULE__, :pipeline, nil)
    end
  end

  @doc """
  Defines a stopwords type analyzer.

  An Analyzer capable of removing specified tokens from the input.

  Refer to the [ArangoDB Stopwords Docs](https://www.arangodb.com/docs/stable/analyzers.html#stopwords) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `stopwords` - (list of strings) - array of strings that describe the tokens to be discarded.
      * `hex` - (boolean) - If false (default), then each string in stopwords is used verbatim.
  """
  defmacro stopwords(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :stopwords,
          :hex
        ])

      analyzer = %{
        name: name,
        type: :stopwords,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a segmentation type analyzer.

  An Analyzer capable of breaking up the input text into tokens in a language-agnostic manner as per Unicode Standard Annex #29,
  making it suitable for mixed language strings.

  Refer to the [ArangoDB Segmentation Docs](https://www.arangodb.com/docs/stable/analyzers.html#segmentation) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `break` - (atom) - character to break at
        * `:all` - return all tokens
        * `:alpha` - return tokens composed of alphanumeric characters only (default). Alphanumeric characters are Unicode codepoints from the
          Letter and Number categories, see Unicode Technical Note #36.
        * `:graphic` - return tokens composed of non-whitespace characters only. Note that the list of whitespace characters does not include line breaks:
          * `U+0009` Character Tabulation
          * `U+0020` Space
          * `U+0085` Next Line
          * `U+00A0` No-break Space
          * `U+1680` Ogham Space Mark
          * `U+2000` En Quad
          * `U+2028` Line Separator
          * `U+202F` Narrow No-break Space
          * `U+205F` Medium Mathematical Space
          * `U+3000` Ideographic Space
      * `case` - (atom) - option of how to store case
        * `:lower` - to convert to all lower-case characters
        * `:upper` - to convert to all upper-case characters
        * `:none` - to not change character case (default)
  """
  defmacro segmentation(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :break,
          :graphic,
          :case
        ])

      analyzer = %{
        name: name,
        type: :segmentation,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a minhash type analyzer.

  An Analyzer that computes so called MinHash signatures using a locality-sensitive hash function. It applies an Analyzer of
  your choice before the hashing, for example, to break up text into words.

  Refer to the [ArangoDB MinHash Docs](https://www.arangodb.com/docs/stable/analyzers.html#minhash) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below
      * `analyzer` - block with one analyzer (if more then one is supplied, only the last will be used

  ## Properties

      * `numHashes` - (number) - the size of the MinHash signature.
  """
  defmacro minhash(name, features, properties, block) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [:numHashes])

      Module.put_attribute(__MODULE__, :pipeline, [])

      try do
        unquote(block)
      after
        :ok
      end

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if Enum.empty?(pipeline) do
        raise ArgumentError,
              "no analyzer was provided for analyzer '#{name}', an analyzer in the do block is required"
      end

      Module.put_attribute(__MODULE__, :analyzers, %{
        name: name,
        type: :minhash,
        features: features,
        analyzer: List.first(pipeline)
      })

      Module.put_attribute(__MODULE__, :pipeline, nil)
    end
  end

  @doc """
  Defines a classification type analyzer.

  An Analyzer capable of classifying tokens in the input text.

  Refer to the [ArangoDB Classification Docs](https://www.arangodb.com/docs/stable/analyzers.html#classification) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `model_location` - (string) - the on-disk path to the trained fastText supervised model.
      * `top_k` - (number) - the number of class labels that will be produced per input (default: 1).
      * `threshold` - (number) - the probability threshold for which a label will be assigned to an input. A fastText
        model produces a probability per class label, and this is what will be filtered (default: 0.99).
  """
  defmacro classification(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :model_location,
          :top_k,
          :threshold
        ])

      analyzer = %{
        name: name,
        type: :classification,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a nearest_neighbors type analyzer.

  An Analyzer capable of finding nearest neighbors of tokens in the input.

  Refer to the [ArangoDB Nearest Neighbors Docs](https://www.arangodb.com/docs/stable/analyzers.html#nearest_neighbors) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `model_location` - (string) - the on-disk path to the trained fastText supervised model.
      * `top_k` - (number) - the number of class labels that will be produced per input (default: 1).
  """
  defmacro nearest_neighbors(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :model_location,
          :top_k
        ])

      analyzer = %{
        name: name,
        type: :nearest_neighbors,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a geojson type analyzer.

  An Analyzer capable of breaking up a GeoJSON object or coordinate array in [longitude, latitude] order into a set
  of indexable tokens for further usage with ArangoSearch Geo functions.

  Refer to the [ArangoDB GeoJSON Docs](https://www.arangodb.com/docs/stable/analyzers.html#geojson) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `type` - (atom) - type of geojson object
        * `:shape` (default) - index all GeoJSON geometry types (Point, Polygon etc.)
        * `:centroid` - compute and only index the centroid of the input geometry
        * `:point` - only index GeoJSON objects of type Point, ignore all other geometry types
      * `options` - (map) - options for fine-tuning geo queries. These options should generally remain unchanged 
        * `:maxCells` (number, optional) - maximum number of S2 cells (default: 20)
        * `:minLevel` (number, optional) - the least precise S2 level (default: 4)
        * `:maxLevel` (number, optional) - the most precise S2 level (default: 23)

  """
  defmacro geojson(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :type,
          :options
        ])

      analyzer = %{
        name: name,
        type: :geojson,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a geo_s2 type analyzer.

  An Analyzer capable of breaking up a GeoJSON object or coordinate array in [longitude, latitude] order into a set of indexable
  tokens for further usage with ArangoSearch Geo functions.

  Refer to the [ArangoDB Geo S2 Docs](https://www.arangodb.com/docs/stable/analyzers.html#geo_s2) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `format` - (atom) - the internal binary representation to use for storing the geo-spatial data in an index 
        * `:latLngDouble` (default) - store each latitude and longitude value as an 8-byte floating-point value
          (16 bytes per coordinate pair). This format preserves numeric values exactly and is more compact than the
          VelocyPack format used by the geojson Analyzer.
        * `:latLngInt` - store each latitude and longitude value as an 4-byte integer value (8 bytes per coordinate
          pair). This is the most compact format but the precision is limited to approximately 1 to 10 centimeters.
        * `:s2Point` - store each longitude-latitude pair in the native format of Google S2 which is used for
          geo-spatial calculations (24 bytes per coordinate pair). This is not a particular compact format but it
          reduces the number of computations necessary when you execute geo-spatial queries. This format preserves
          numeric values exactly.
      * `type` - (atom) - type of geojson object
        * `:shape` (default) - index all GeoJSON geometry types (Point, Polygon etc.)
        * `:centroid` - compute and only index the centroid of the input geometry
        * `:point` - only index GeoJSON objects of type Point, ignore all other geometry types
      * `options` - (map) - options for fine-tuning geo queries. These options should generally remain unchanged 
        * `:maxCells` (number, optional) - maximum number of S2 cells (default: 20)
        * `:minLevel` (number, optional) - the least precise S2 level (default: 4)
        * `:maxLevel` (number, optional) - the most precise S2 level (default: 23)

  """
  defmacro geo_s2(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :format,
          :type,
          :options
        ])

      analyzer = %{
        name: name,
        type: :geo_s2,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc """
  Defines a geopoint type analyzer.

  An Analyzer capable of breaking up a coordinate array in [latitude, longitude] order or a JSON object describing a
  coordinate pair using two separate attributes into a set of indexable tokens for further usage with ArangoSearch Geo functions.

  Refer to the [ArangoDB Geo Point Docs](https://www.arangodb.com/docs/stable/analyzers.html#geopoint) for more info.

  ## Parameters

      * `name` - atom of the analyzer name
      * `features` - the features options to be set (see [Analyzer Features](https://hexdocs.pm/arangox_ecto/ArangoXEcto.Analyzer.html#module-features))
      * `properties` - a map of the properties to be set, see below

  ## Properties

      * `latitude` - (list of string) - list of strings that describes the attribute path of the latitude value
        relative to the field for which the Analyzer is defined in the View
      * `longitude` - (list of string) - list of strings that describes the attribute path of the longitude value
        relative to the field for which the Analyzer is defined in the View
      * `options` - (map) - options for fine-tuning geo queries. These options should generally remain unchanged 
        * `:maxCells` (number, optional) - maximum number of S2 cells (default: 20)
        * `:minLevel` (number, optional) - the least precise S2 level (default: 4)
        * `:maxLevel` (number, optional) - the most precise S2 level (default: 23)

  """
  defmacro geopoint(name, features, properties \\ %{}) do
    quote do
      name = ArangoXEcto.Analyzer.validate_name(unquote(name))
      features = ArangoXEcto.Analyzer.validate_features(unquote(features))

      properties =
        ArangoXEcto.Analyzer.validate_properties(unquote(properties), name, [
          :latitude,
          :longitude,
          :options
        ])

      analyzer = %{
        name: name,
        type: :geopoint,
        features: features,
        properties: properties
      }

      pipeline = Module.get_attribute(__MODULE__, :pipeline)

      if is_nil(pipeline) do
        Module.put_attribute(__MODULE__, :analyzers, analyzer)
      else
        # in pipeline
        Module.put_attribute(__MODULE__, :pipeline, [analyzer | pipeline])
      end
    end
  end

  @doc false
  @spec validate_name(atom()) :: atom()
  def validate_name(name) when is_atom(name), do: name

  def validate_name(name),
    do: raise(ArgumentError, "the name for analyzer must be an atom, got: #{inspect(name)}")

  @valid_keys [:frequency, :norm, :position]

  @doc false
  @spec validate_features([atom()]) :: [atom()]
  def validate_features(features) do
    unless is_list(features) and Enum.all?(features, &Enum.member?(@valid_keys, &1)) do
      raise ArgumentError,
            "the features provided are invalid, only accepts keys [:frequency, :norm, :position], got: #{inspect(features)}"
    end

    features
  end

  @doc false
  @spec validate_properties([atom()], atom(), [atom()]) :: [atom()]
  def validate_properties(properties, name, valid_keys) do
    Enum.all?(properties, fn {k, v} ->
      Enum.member?(valid_keys, k) and valid_key?(k, v)
    end)
    |> unless do
      raise ArgumentError,
            "the properties provided for analyzer '#{name}' are invalid, only accepts keys #{inspect(valid_keys)}, got: #{inspect(properties)}"
    end

    properties
  end

  defp valid_key?(:delimiter, value), do: is_binary(value)
  defp valid_key?(:locale, value), do: is_binary(value)
  defp valid_key?(:accent, value), do: is_boolean(value)
  defp valid_key?(:case, value), do: value in [:none, :lower, :upper]
  defp valid_key?(:min, value), do: is_integer(value)
  defp valid_key?(:max, value), do: is_integer(value)
  defp valid_key?(:preserveOriginal, value), do: is_boolean(value)
  defp valid_key?(:startMarker, value), do: is_binary(value)
  defp valid_key?(:endMarker, value), do: is_binary(value)
  defp valid_key?(:streamType, value), do: value in [:binary, :utf8]
  defp valid_key?(:stemming, value), do: is_boolean(value)
  defp valid_key?(:stopwords, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp valid_key?(:stopwordsPath, value), do: is_binary(value)
  defp valid_key?(:queryString, value), do: is_binary(value)
  defp valid_key?(:collapsePositions, value), do: is_boolean(value)
  defp valid_key?(:keepNull, value), do: is_boolean(value)
  defp valid_key?(:batchSize, value), do: is_integer(value) and value >= 1 and value <= 1000
  defp valid_key?(:numHashes, value), do: is_integer(value) and value >= 1
  defp valid_key?(:hex, value), do: is_boolean(value)
  defp valid_key?(:model_location, value), do: is_binary(value)
  defp valid_key?(:top_k, value), do: is_integer(value)
  defp valid_key?(:threshold, value), do: is_float(value) or is_integer(value)
  defp valid_key?(:latitude, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp valid_key?(:longitude, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp valid_key?(:returnType, value), do: value in [:string, :number, :bool]
  defp valid_key?(:break, value), do: value in [:all, :alpha, :graphic]
  defp valid_key?(:type, value), do: value in [:shape, :centroid, :point]
  defp valid_key?(:format, value), do: value in [:latLngDouble, :latLngInt, :s2Point]

  defp valid_key?(:memoryLimit, value),
    do: is_integer(value) and value >= 1_048_576 and value <= 33_554_432

  defp valid_key?(:edgeNgram, value),
    do:
      is_map(value) and
        Enum.all?(value, fn {k, v} ->
          k in [:min, :max, :preserveOriginal] and valid_key?(k, v)
        end)

  defp valid_key?(:options, value),
    do:
      is_map(value) and
        Enum.all?(value, fn {k, v} ->
          k in [:maxCells, :minLevel, :maxLevel] and is_integer(v)
        end)
end
