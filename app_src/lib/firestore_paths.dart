class P {
  static const users = 'users', lists = 'lists', members = 'members', invites = 'invites';
  static const inventory = 'inventory', shopping = 'shopping', archive = 'archive', notices = 'notices';
  static String user(String uid) => 'users/$uid';
  static String list(String id) => 'lists/$id';
  static String member(String l, String uid) => 'lists/$l/members/$uid';
}
