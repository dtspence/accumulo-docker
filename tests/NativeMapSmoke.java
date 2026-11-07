/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import java.util.Iterator;
import java.util.Map;
import org.apache.accumulo.core.data.Key;
import org.apache.accumulo.core.data.Value;
import org.apache.accumulo.tserver.NativeMap;

public class NativeMapSmoke {
  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }

  public static void main(String[] args) {
    System.load("/opt/accumulo/lib/native/libaccumulo.so");
    NativeMap map = new NativeMap();
    try {
      Key a = new Key("a");
      Key b = new Key("b");
      map.put(b, new Value("second"));
      map.put(a, new Value("first"));
      require(map.size() == 2, "size");
      require(new Value("first").equals(map.get(a)), "get");
      require(map.get(new Key("missing")) == null, "missing key");
      Iterator<Map.Entry<Key,Value>> entries = map.iterator();
      require(entries.hasNext() && entries.next().getKey().equals(a), "first key");
      require(entries.hasNext() && entries.next().getKey().equals(b), "second key");
      require(!entries.hasNext(), "iteration end");
    } finally {
      map.delete();
    }
    try {
      map.size();
      throw new AssertionError("deleted map remained usable");
    } catch (IllegalStateException expected) {
      System.out.println("NativeMap JNI smoke test passed");
    }
  }
}
