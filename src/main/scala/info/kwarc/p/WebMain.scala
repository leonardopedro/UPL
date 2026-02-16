package info.kwarc.p

import scala.scalajs.js
import scala.scalajs.js.annotation._

@JSExportTopLevel("UPL")
@JSExportAll
object WebMain {
  val checker = new Checker(ErrorThrower)
  def checkProgram(input: String) = {
    val voc = Parser.text(SourceOrigin.anonymous, input, ErrorThrower)
    val prog = Program(voc, UnitValue)
    checker.checkProgram(prog)
  }

  def checkIn(prog: Program, input: String) = {
    val gc = GlobalContext(prog.voc)
    val voc = Parser.text(SourceOrigin.anonymous, input, ErrorThrower)
    checker.checkVocabulary(gc,voc,true)(voc)
  }

  def runIn(prog: Program, expS: String) = {
    val parser = new Parser(SourceOrigin.anonymous,expS, ErrorThrower)
    val exp = parser.parseExpression(PContext.empty)
    val (expC,expI) = checker.checkAndInferExpression(GlobalContext(prog.voc), exp)
    val intp = new Interpreter(prog.voc)
    intp.interpretExpression(expC)
  }

  def run(input: String, mnS: String) : String = {
    val prog = checkProgram(input)
    val r = runIn(prog, mnS)
    print(r)
  }

  def runToJS(input: String, mnS: String): js.Any = {
    val prog = checkProgram(input)
    val r = runIn(prog, mnS)
    toJS(r)
  }

  def emptyProgram = Program(Theory.empty, UnitValue)

  def toJS(exp: Expression): js.Any = exp match {
    case UnitValue => null
    case BoolValue(v) => v
    case StringValue(v) => v
    case NumberValue(_, re, im) =>
      if (im.zero) re.approx.value
      else js.Dynamic.literal(re = re.approx.value, im = im.approx.value)
    case Tuple(es) => js.Array(es.map(toJS): _*)
    case CollectionValue(es, _) => js.Array(es.map(toJS): _*)
    case inst: Instance =>
      val dict = js.Dictionary[js.Any]()
      inst.fields.foreach { f => dict(f.name) = toJS(f.value) }
      dict
    case Lambda(ins, body, _) =>
      js.Dynamic.literal(
        "kind" -> "lambda",
        "inputs" -> js.Array(ins.variables.map(vd => js.Dynamic.literal(
          "name" -> vd.name,
          "type" -> vd.tp.toString
        )): _*),
        "body" -> toJS(body)
      )
    case Application(fun, args) =>
      js.Dynamic.literal(
        "kind" -> "application",
        "function" -> toJS(fun),
        "arguments" -> js.Array(args.map(toJS): _*)
      )
    case VarRef(n) => js.Dynamic.literal("kind" -> "variable", "name" -> n)
    case ClosedRef(n) => js.Dynamic.literal("kind" -> "reference", "name" -> n)
    case BaseOperator(op, _) => js.Dynamic.literal("kind" -> "operator", "symbol" -> op.symbol)
    case ExprOver(_, e) => js.Dynamic.literal("kind" -> "quote", "expression" -> toJS(e))
    case Eval(e) => js.Dynamic.literal("kind" -> "eval", "expression" -> toJS(e))
    case _ => exp.toString
  }

  def print(sf: SyntaxFragment) = sf.toString
}
