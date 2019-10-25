# 1
## 2
### 3
#### 4
##### 5

if true:
  # 1
  ## 2
  ### 3
  #### 4
  ##### 5
  let a = 1 # 1a
  let b = 2 ## 2b
  let c = 3 ### 3c

type
  NameInstance = tuple[filename: string, linenum, colnum: int]

var name_instance: NameInstance
var name_instance2: NameInstance
var name_instance3: NameInstance
echo name_instance
echo name_instance
