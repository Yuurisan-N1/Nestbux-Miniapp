Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule Nestbuxbot do
  @moduledoc false

  @my_project "Nestbuxbot Miniapp"
  @app_base "https://nest-coin-quest.lovable.app"
  @server_fn @app_base <>
               "/_serverFn/f87828ba5b3b221783a38ddae9430da1ac262b771ca287aebf2df9a3c3873b89"
  @user_agent "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  @root __DIR__

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"
  @erase "\e[K"

  @ad_gap 1
  @spin_ad_gap 1
  @wheel_gap 1
  @retry_gap 15
  @max_attempts 8

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:crypto)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    Enum.with_index(accounts)
    |> Enum.each(fn {account, index} ->
      if index > 0, do: IO.puts("")

      proxy = proxy_for(proxies, index)

      case proxy do
        nil -> :ok
        line -> yellow("Using proxy #{mask_proxy(line)}")
      end

      try do
        process_account(account, index, proxy)
      rescue
        _error -> red("Account #{index + 1} was skipped after an error")
      end
    end)

    yellow("Cycle #{cycle} is complete and every account was processed")

    countdown(sleep_seconds(settings), "Next cycle starts in")
    Banner.show_banner(@my_project)
    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(account, index, proxy) do
    case identity(account) do
      {:ok, id, username, _first_name} ->
        device = device_for(id)

        case bootstrap(account, device, proxy) do
          {:ok, state} ->
            user = get(state, "user", %{})
            name = first_present([get(user, "username"), get(user, "first_name"), username])
            balance = trunc_number(get(user, "balance", 0))
            unit = coin_name(state)

            green(
              "Player #{shorten(clean_text(name, "player"), "player", 14)} signed in with a balance of #{balance} #{unit}"
            )

            process_tasks(account, state, proxy)
            process_spin_ads(account, state, proxy)
            process_wheel(account, state, proxy)
            process_coin_ads(account, state, proxy)
            summarise(account, device, proxy, balance, unit)

          {:gate, channels} ->
            yellow(
              "Join #{shorten(clean_text(channels, "the required channels"), "the required channels", 32)} first and then reopen this account"
            )

          {:error, "unauthorized"} ->
            red("Telegram could not verify this account and it was refused")

          {:error, "banned"} ->
            red("This account is banned and it was skipped for this cycle")

          {:error, reason} ->
            red(
              "Account #{index + 1} could not start with #{shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 24)}"
            )
        end

      {:error, reason} ->
        red(
          "Account #{index + 1} initData was refused with #{shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 24)}"
        )
    end
  end

  defp bootstrap(account, device, proxy) do
    case call(account, "bootstrap", %{"device" => device_string(device)}, proxy) do
      {:ok, inner} ->
        case get(inner, "data") do
          %{} = data -> {:ok, data}
          _other -> {:error, "the account data could not be read"}
        end

      {:gate, channels} ->
        {:gate, channels}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_tasks(account, state, proxy) do
    tasks = get(state, "tasks", [])
    {pending, resting} = Enum.split_with(tasks, &claimable?/1)

    cond do
      tasks == [] ->
        yellow("The task list is not published for this account yet")

      pending == [] and Enum.all?(resting, &(resting_reason(&1) == :done)) ->
        yellow("Every available account task was already completed")

      pending == [] ->
        yellow("No account task can be claimed right now")
        report_resting(resting)

      true ->
        green("Found #{plural(length(pending), "task")} to process")
        walk_tasks(pending, account, proxy)
        report_resting(resting)
    end
  end

  defp claimable?(task), do: not api_boolean(get(task, "completed", false))

  defp resting_reason(task) do
    if api_boolean(get(task, "completed", false)), do: :done, else: :review
  end

  defp report_resting(resting) do
    resting
    |> Enum.map(&resting_reason/1)
    |> Enum.frequencies()
    |> Enum.each(fn {reason, count} -> yellow(skip_text(reason, count)) end)
  end

  defp skip_text(:done, count), do: "#{plural(count, "task")} were already completed earlier"
  defp skip_text(:review, count), do: "#{plural(count, "task")} still wait for a manual review"

  defp walk_tasks(tasks, account, proxy) do
    total = length(tasks)

    tasks
    |> Enum.with_index(1)
    |> Enum.each(fn {task, index} ->
      task_progress(index, total)
      claim_task(account, task, proxy)
    end)

    clear_progress()
  end

  defp task_progress(index, total) do
    text = "Checking task #{index} of #{total}"
    IO.write("\r" <> @erase <> @yellow <> @bold <> text <> @reset)
  end

  defp clear_progress do
    IO.write("\r" <> @erase)
  end

  defp claim_task(account, task, proxy) do
    title =
      shorten(
        clean_text(get(task, "title", get(task, "chat_username", "task")), "task"),
        "task",
        24
      )

    outcome =
      case claim_with_retry(account, %{"taskId" => get(task, "id")}, proxy) do
        {:ok, data} -> {:claimed, trunc_number(get(data, "reward", get(task, "reward", 0)))}
        {:error, "already_completed"} -> :done
        {:error, "not_joined"} -> :join
        {:error, reason} when reason in ["task_unavailable", "task_gone"] -> :gone
        {:error, reason} -> {:refused, shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 20)}
      end

    clear_progress()
    log_task(title, outcome)
  end

  defp log_task(title, {:claimed, reward}),
    do: green("Task #{title} was claimed earning #{reward} coins")

  defp log_task(title, :join), do: yellow("Task #{title} still needs a manual channel join")
  defp log_task(title, :done), do: yellow("Task #{title} was already completed earlier")
  defp log_task(title, :gone), do: yellow("Task #{title} is no longer available")

  defp log_task(title, {:refused, reason}),
    do: yellow("Task #{title} was refused by the server with #{reason}")

  defp process_spin_ads(account, state, proxy) do
    left = trunc_number(get(state, "adsLeft", 0))

    if left <= 0 do
      yellow("The daily spin ad limit is reached and those ads stop")
    else
      spin_ad_walk(account, proxy, left)
    end
  end

  defp spin_ad_walk(_account, _proxy, 0), do: :ok

  defp spin_ad_walk(account, proxy, left) do
    case retry_action(account, "ad_spin", %{}, proxy, "Next ad in") do
      {:ok, data} ->
        green("Watched an ad and one bonus spin was credited")
        next = trunc_number(get(data, "ads_left", left - 1))

        if next > 0 do
          countdown(@spin_ad_gap, "Next ad in")
          spin_ad_walk(account, proxy, next)
        end

      {:error, reason} when reason in ["ad_limit", "daily_limit"] ->
        yellow("The daily spin ad limit is reached and those ads stop")

      {:error, reason} ->
        yellow(
          "Bonus spins could not be collected because of #{shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 20)}"
        )
    end
  end

  defp process_coin_ads(account, state, proxy) do
    left = trunc_number(get(state, "coinAdsLeft", 0))

    if left <= 0 do
      yellow("The daily ad limit is reached and the ads stop for now")
    else
      coin_ad_walk(account, proxy, left)
    end
  end

  defp coin_ad_walk(_account, _proxy, 0), do: :ok

  defp coin_ad_walk(account, proxy, left) do
    case retry_action(account, "ad_coins", %{}, proxy, "Next ad in") do
      {:ok, data} ->
        reward = trunc_number(get(data, "reward", 0))
        green("Watched an ad and #{reward} coins were credited to this account")

        if left > 1 do
          countdown(@ad_gap, "Next ad in")
          coin_ad_walk(account, proxy, left - 1)
        end

      {:error, reason} when reason in ["ad_limit", "daily_limit"] ->
        yellow("The daily ad limit is reached and the ads stop for now")

      {:error, reason} ->
        yellow(
          "Ad rewards could not be collected because of #{shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 20)}"
        )
    end
  end

  defp process_wheel(account, state, proxy) do
    left = trunc_number(get(state, "spinsLeft", 0))

    if left <= 0 do
      yellow("No spins are left today and the wheel stops for now")
    else
      wheel_walk(account, proxy, left)
    end
  end

  defp wheel_walk(_account, _proxy, 0), do: :ok

  defp wheel_walk(account, proxy, left) do
    case retry_action(account, "spin", %{}, proxy, "Next spin in") do
      {:ok, data} ->
        amount = trunc_number(get(data, "amount", 0))
        label = shorten(clean_text(get(data, "label", "a reward"), "a reward"), "a reward", 20)
        green("Spin landed on #{label} and #{amount} coins were credited")

        if left > 1 do
          countdown(@wheel_gap, "Next spin in")
          wheel_walk(account, proxy, left - 1)
        end

      {:error, reason} when reason in ["daily_limit", "not_configured"] ->
        yellow("No spins are left today and the wheel stops for now")

      {:error, reason} ->
        yellow(
          "The wheel could not be spun because of #{shorten(clean_text(reason, "an unknown reason"), "an unknown reason", 20)}"
        )
    end
  end

  defp summarise(account, device, proxy, before, unit) do
    case bootstrap(account, device, proxy) do
      {:ok, state} ->
        after_balance = trunc_number(get(get(state, "user", %{}), "balance", before))
        earned = max(after_balance - before, 0)
        green("Account totals #{after_balance} #{unit} with #{earned} #{unit} earned in this cycle")

      _other ->
        yellow("The final account summary could not be read this cycle")
    end
  end

  defp retry_action(account, action, payload, proxy, label, attempt \\ 1)

  defp retry_action(_account, _action, _payload, _proxy, _label, attempt) when attempt > @max_attempts do
    {:error, "rate_limited"}
  end

  defp retry_action(account, action, payload, proxy, label, attempt) do
    case call(account, action, payload, proxy) do
      {:ok, inner} ->
        {:ok, result_of(inner)}

      {:error, "rate_limited"} ->
        countdown(@retry_gap, label)
        retry_action(account, action, payload, proxy, label, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claim_with_retry(account, payload, proxy, attempt \\ 1)

  defp claim_with_retry(_account, _payload, _proxy, attempt) when attempt > @max_attempts do
    {:error, "rate_limited"}
  end

  defp claim_with_retry(account, payload, proxy, attempt) do
    case call(account, "claim_task", payload, proxy) do
      {:ok, inner} ->
        {:ok, result_of(inner)}

      {:error, "rate_limited"} ->
        countdown(@retry_gap, "Next task in")
        claim_with_retry(account, payload, proxy, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp result_of(inner) do
    case get(inner, "result") do
      %{} = result -> result
      _other -> %{}
    end
  end

  defp call(account, action, payload, proxy) do
    envelope = %{
      "data" => %{"initData" => account, "action" => action, "payload" => payload}
    }

    body = %{"t" => srv_encode(envelope), "f" => 127, "m" => []}

    case request(body, proxy) do
      {:ok, value} ->
        inner = get(value, "result")

        cond do
          not is_map(inner) ->
            {:error, "the server answer could not be read"}

          not api_boolean(get(inner, "ok", false)) ->
            case get(inner, "error") do
              "must_join" -> {:gate, get(inner, "channel", "")}
              other -> {:error, to_string(other)}
            end

          true ->
            {:ok, inner}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(body, proxy) do
    url = String.to_charlist(@server_fn)
    {profile, auth} = proxy_setup(proxy)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"accept", ~c"application/x-tss-framed, application/x-ndjson, application/json"},
      {~c"x-tsr-serverfn", ~c"true"},
      {~c"accept-language", ~c"en-US,en;q=0.9"},
      {~c"origin", String.to_charlist(@app_base)},
      {~c"referer", String.to_charlist(@app_base <> "/")},
      {~c"user-agent", String.to_charlist(@user_agent)}
    ]

    options = [ssl: [verify: :verify_none], timeout: 45_000, connect_timeout: 20_000] ++ auth
    payload = YuurisanJSON.encode(body)

    case dispatch(url, headers, payload, options, profile) do
      {:ok, {{_, status, _}, _, response}} when status >= 200 and status < 300 ->
        case YuurisanJSON.decode(IO.iodata_to_binary(response)) do
          {:ok, value} -> {:ok, srv_decode(value)}
          {:error, _} -> {:error, "the server answer could not be read"}
        end

      {:ok, {{_, _status, _}, _, response}} ->
        case YuurisanJSON.decode(IO.iodata_to_binary(response)) do
          {:ok, value} -> classify(srv_decode(value))
          {:error, _} -> {:error, "the server refused the request"}
        end

      {:error, reason} ->
        {:error, stringify(reason, "an unknown reason")}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp dispatch(url, headers, payload, options, profile) do
    :httpc.request(
      :post,
      {url, headers, ~c"application/json", payload},
      options,
      [body_format: :binary],
      profile
    )
  end

  defp classify(value) do
    message = get(get(value, "s", %{}), "message", "")

    if is_binary(message) and message != "" do
      {:error, message}
    else
      {:error, "the server refused the request"}
    end
  end

  defp srv_encode(value) when is_nil(value), do: %{"t" => 2, "s" => 0}
  defp srv_encode(true), do: %{"t" => 2, "s" => 2}
  defp srv_encode(false), do: %{"t" => 2, "s" => 3}
  defp srv_encode(value) when is_integer(value), do: %{"t" => 0, "s" => value}
  defp srv_encode(value) when is_float(value), do: %{"t" => 0, "s" => value}
  defp srv_encode(value) when is_binary(value), do: %{"t" => 1, "s" => value}

  defp srv_encode(value) when is_list(value) do
    %{"t" => 9, "i" => 0, "a" => Enum.map(value, &srv_encode/1), "o" => 0}
  end

  defp srv_encode(value) when is_map(value) do
    keys = Map.keys(value)

    %{
      "t" => 10,
      "i" => 0,
      "p" => %{"k" => keys, "v" => Enum.map(keys, fn key -> srv_encode(Map.get(value, key)) end)},
      "o" => 0
    }
  end

  defp srv_encode(value), do: srv_encode(to_string(value))

  defp srv_decode(value) when is_map(value) do
    case get(value, "t") do
      kind when kind in [0, 1] ->
        get(value, "s")

      2 ->
        srv_constant(get(value, "s"))

      9 ->
        value |> get("a", []) |> Enum.map(&srv_decode/1)

      kind when kind in [10, 11] ->
        pairs = get(value, "p", %{})
        keys = get(pairs, "k", [])
        items = get(pairs, "v", [])

        keys
        |> Enum.zip(items)
        |> Map.new(fn {key, item} -> {key, srv_decode(item)} end)

      _other ->
        nil
    end
  end

  defp srv_decode(value), do: value

  defp srv_constant(0), do: nil
  defp srv_constant(2), do: true
  defp srv_constant(3), do: false
  defp srv_constant(_other), do: nil

  defp identity(init_data) do
    with {:ok, params} <- parse_query(init_data),
         raw when is_binary(raw) <- Map.get(params, "user"),
         {:ok, user} <- YuurisanJSON.decode(URI.decode_www_form(raw)),
         id when not is_nil(id) <- get(user, "id") do
      {:ok, to_string(id), get(user, "username", ""), get(user, "first_name", "")}
    else
      nil -> {:error, "the user object is missing"}
      {:error, reason} -> {:error, reason}
      _other -> {:error, "initData could not be read"}
    end
  end

  defp parse_query(raw) do
    pairs =
      raw
      |> String.trim()
      |> String.split("&")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [key, value] -> {key, value}
          [key] -> {key, ""}
        end
      end)

    if Enum.any?(pairs, fn {key, _value} -> key == "hash" end) do
      {:ok, Map.new(pairs)}
    else
      {:error, "initData has no hash field"}
    end
  end

  defp device_for(id) do
    path = Path.join(@root, "device.json")
    cache = load_device_cache(path)

    case Map.get(cache, id) do
      %{} = record ->
        record

      _other ->
        record = build_device()
        File.write(path, YuurisanJSON.encode_pretty(Map.put(cache, id, record)))
        record
    end
  end

  defp load_device_cache(path) do
    case File.read(path) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, value} when is_map(value) -> value
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp build_device do
    {width, height, ratio, language, cores, zone} = Enum.random(device_pool())

    %{
      "sw" => width,
      "sh" => height,
      "dpr" => ratio,
      "lang" => language,
      "hc" => cores,
      "tz" => zone
    }
  end

  defp device_pool do
    [
      {412, 915, 2.625, "en-US", 8, "Asia/Shanghai"},
      {412, 892, 2.625, "en-GB", 8, "Asia/Singapore"},
      {393, 851, 2.75, "en-US", 6, "Asia/Jakarta"},
      {360, 800, 3.0, "en-US", 8, "Asia/Manila"},
      {384, 832, 2.8125, "en-US", 8, "Asia/Kolkata"},
      {412, 916, 2.625, "en-US", 8, "Asia/Dubai"},
      {360, 780, 3.0, "en-US", 8, "Asia/Ho_Chi_Minh"},
      {393, 873, 2.75, "en-US", 6, "Asia/Bangkok"},
      {412, 915, 1.75, "en-US", 8, "Asia/Tokyo"},
      {384, 854, 2.8125, "en-AU", 8, "Australia/Sydney"}
    ]
  end

  defp device_string(device) do
    [
      get(device, "sw", 412),
      get(device, "sh", 915),
      get(device, "dpr", 2.625),
      get(device, "lang", "en-US"),
      get(device, "hc", 8),
      get(device, "tz", "Asia/Shanghai")
    ]
    |> Enum.join("|")
  end

  defp coin_name(state) do
    clean_text(get(get(state, "settings", %{}), "coin_name", "coins"), "coins")
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} -> :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)
      {:error, {:already_started, _pid}} -> :ok
      _other -> :ok
    end

    case user do
      "" -> {name, []}
      _other -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(@root, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(@root, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, value} -> value
          {:error, _reason} -> default_settings()
        end

      {:error, _reason} ->
        settings = default_settings()
        File.write(Path.join(@root, "config.json"), YuurisanJSON.encode_pretty(settings))
        settings
    end
  end

  defp default_settings, do: %{"settings" => %{"sleep_seconds" => 3600}}

  defp sleep_seconds(settings) do
    case get(get(settings, "settings", %{}), "sleep_seconds", 3600) do
      value when is_integer(value) and value > 0 -> value
      value when is_float(value) and value > 0 -> trunc(value)
      _other -> 3600
    end
  end

  defp first_present(values) do
    Enum.find(values, fn value -> is_binary(value) and value != "" end) || ""
  end

  defp api_boolean(value) when is_boolean(value), do: value
  defp api_boolean(value) when is_number(value), do: value == 1

  defp api_boolean(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["1", "true", "yes"]
  end

  defp api_boolean(_other), do: false

  defp get(map, key, default \\ nil)
  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp trunc_number(value) when is_integer(value), do: value
  defp trunc_number(value) when is_float(value), do: trunc(value)

  defp trunc_number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, _rest} -> number
      _other -> 0
    end
  end

  defp trunc_number(_value), do: 0

  defp clean_text(value, fallback) when is_binary(value) do
    text =
      String.replace(
        value,
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp clean_text(value, fallback), do: stringify(value, fallback)

  defp stringify(:timeout, _fallback), do: "the request timed out"
  defp stringify(:econnrefused, _fallback), do: "the connection was refused"
  defp stringify(:nxdomain, _fallback), do: "the host could not be resolved"
  defp stringify(value, _fallback) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value, _fallback) when is_number(value), do: to_string(value)
  defp stringify(value, _fallback) when is_list(value), do: List.to_string(value)
  defp stringify({:failed_connect, _reason}, _fallback), do: "no network connection"
  defp stringify({:failed_connect, _reason, _host}, _fallback), do: "no network connection"
  defp stringify({:timeout, _reason}, _fallback), do: "the request timed out"
  defp stringify({:error, reason}, fallback), do: clean_text(reason, fallback)
  defp stringify(_value, fallback), do: fallback

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    for signal <- [:sigterm, :sighup, :sigquit] do
      try do
        System.trap_signal(signal, handler)
      rescue
        _error -> :ok
      end
    end
  end

  defp shorten(value, fallback, limit) do
    text = to_string(value)

    cond do
      text == "" ->
        fallback

      String.length(text) <= limit ->
        text

      true ->
        trimmed =
          text
          |> String.slice(0, limit)
          |> String.split(" ")
          |> Enum.drop(-1)
          |> Enum.join(" ")

        if trimmed == "" do
          String.slice(text, 0, limit)
        else
          trimmed
        end
    end
  end

  defp plural(count, word) do
    if count == 1, do: "#{count} #{word}", else: "#{count} #{pluralize(word)}"
  end

  defp pluralize(word) do
    if String.ends_with?(word, "y") do
      String.slice(word, 0, String.length(word) - 1) <> "ies"
    else
      word <> "s"
    end
  end

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> message <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> message <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> message <> @reset)
end

Nestbuxbot.run()
