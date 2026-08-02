if (.validators | type) != "array" then
  error("blueprint validators must be an array")
else
  [.validators[] | select(.title == $title)] as $matches
  | if ($matches | length) != 1 then
      error("expected exactly one validator title: \($title)")
    elif (($matches[0].compiledCode | type) != "string")
      or (($matches[0].compiledCode | length) == 0) then
      error("compiledCode must be a non-empty string: \($title)")
    else
      $matches[0].compiledCode
    end
end
